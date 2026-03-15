/**
 * CustomerOrderLineServiceTest
 * ----------------------------
 * PURPOSE: An end-to-end test that runs a create, update, and delete operation
 * through the service layer in a single test, then checks the database to
 * confirm each operation produced the expected result.
 *
 * CHANGES FROM ORIGINAL:
 *
 * 1. Wrong factory call — CustomerOrderLineTestDataFactory.OrderBundle.createOrderWithItem()
 *    → CustomerOrderLineTestDataFactory.createOrderWithItem()
 *    ===========================================================================================
 *    The original tried to call createOrderWithItem() as if it belonged to the inner
 *    OrderBundle class. But createOrderWithItem() is a static method on the outer
 *    factory class, not on OrderBundle. Calling it via OrderBundle just causes a
 *    compile error. The fix is to call it directly on the factory class.
 *
 * 2. Assert.areEqual(cols.size() > 0, ...) → Assert.isTrue(cols.size() > 0, ...)
 *    =============================================================================
 *    Same broken pattern as in the other test files. Assert.areEqual() with a
 *    true/false expression as the first argument and a string as the second will
 *    always pass because a Boolean is never equal to a String. 
 *    Assert.isTrue() is the correct method to use for true/false conditions.
 *
 * 3. Assert.areEqual(c.Name.startsWith('[DEL]'), ...) → Assert.isTrue(c.Name.startsWith('[DEL]'), ...)
 *    ===================================================================================================
 *    Same issue — see point 2.
 */
@IsTest
private class CustomerOrderLineServiceTest {

    @IsTest
    static void testCreateUpdateDelete_endToEnd() {

        // FIXED: was CustomerOrderLineTestDataFactory.OrderBundle.createOrderWithItem()
        // createOrderWithItem() lives on the factory class, not on the inner OrderBundle class.
        CustomerOrderLineTestDataFactory.OrderBundle b = CustomerOrderLineTestDataFactory.createOrderWithItem();

        // CREATE request
        CustomerOrderLineHandler.RequestWrapper createReq = new CustomerOrderLineHandler.RequestWrapper();
        createReq.operationType = 'create';
        createReq.newRecord     = b.orderItem;

        // UPDATE request (change quantity & subscription term)
        OrderItem oldOI = new OrderItem(Id = b.orderItem.Id);
        oldOI.Quantity                         = 2;
        oldOI.SBQQ__DefaultSubscriptionTerm__c = 24;

        OrderItem newOI = new OrderItem(Id = b.orderItem.Id);
        newOI.Quantity                         = 3;
        newOI.SBQQ__DefaultSubscriptionTerm__c = 36;

        CustomerOrderLineHandler.RequestWrapper updateReq = new CustomerOrderLineHandler.RequestWrapper();
        updateReq.operationType = 'update';
        updateReq.oldRecord     = oldOI;
        updateReq.newRecord     = newOI;

        // DELETE request — pre-create a COL so the delete tag has something to apply to
        CustomerOrderLineTestDataFactory.createColLinkedTo(b.orderItem, 'To be deleted');
        CustomerOrderLineHandler.RequestWrapper deleteReq = new CustomerOrderLineHandler.RequestWrapper();
        deleteReq.operationType    = 'delete';
        deleteReq.deletedRecordId  = b.orderItem.Id;

        Test.startTest();
        CustomerOrderLineService.processRequests(new List<CustomerOrderLineHandler.RequestWrapper>{
            createReq, updateReq, deleteReq
        });
        Test.stopTest();

        List<CustomerOrderLine__c> cols = [
            SELECT Id, Name, Quantity__c, Subscription_Term_Months__c, Last_Synced_Date__c
            FROM CustomerOrderLine__c
            WHERE OrderItem__c = :b.orderItem.Id
        ];

        // FIXED: was Assert.areEqual(cols.size() > 0, '...') — always passed.
        // Assert.isTrue() correctly verifies the condition evaluates to true.
        Assert.isTrue(cols.size() > 0, 'At least one COL should exist after create');

        CustomerOrderLine__c updated = [
            SELECT Id, Quantity__c, Subscription_Term_Months__c, Last_Synced_Date__c
            FROM CustomerOrderLine__c
            WHERE OrderItem__c = :b.orderItem.Id
            ORDER BY Last_Synced_Date__c DESC NULLS LAST
            LIMIT 1
        ];
        Assert.areNotEqual(null, updated.Last_Synced_Date__c, 'Update path should set Last_Synced_Date__c');

        for (CustomerOrderLine__c c : [SELECT Id, Name FROM CustomerOrderLine__c WHERE OrderItem__c = :b.orderItem.Id]) {
            // FIXED: was Assert.areEqual(c.Name.startsWith('[DEL]'), '...') — always passed.
            Assert.isTrue(c.Name.startsWith('[DEL]'), 'After delete handling, Names should be prefixed with [DEL]');
        }
    }
}
