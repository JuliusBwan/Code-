/**
 * CustomerOrderLineHandlerTest
 * ----------------------------
 * PURPOSE: Tests the invocable entry point. Verifies that calling process()
 * with a create request results in a COL being created, and that passing null
 * does not cause an exception.
 *
 * CHANGES FROM ORIGINAL:
 *
 * 1. testInvocableProcess_nullRequests_noThrow — removed vacuous assertion
 *    =======================================================================
 *    The original ended with:
 *        Assert.areEqual(true, 'No exception expected when passing null...');
 *
 *    Assert.areEqual() with two arguments (expected, actual) compares them for
 *    equality. Here it was comparing the Boolean true against the String 'No
 *    exception expected...' — these are never equal, so the assertion always
 *    passed and was testing nothing at all.
 *
 *    The real intent of the test is just: "calling this method with null should
 *    not throw an exception". In Apex, if the method throws, the test fails
 *    automatically. So no assertion is needed at all — the absence of an
 *    exception IS the test passing. The bogus assertion has been removed and
 *    replaced with a comment explaining this.
 */
@IsTest
private class CustomerOrderLineHandlerTest {

    @IsTest
    static void testInvocableProcess_createsCOL() {
        CustomerOrderLineTestDataFactory.OrderBundle b = CustomerOrderLineTestDataFactory.createOrderWithItem();

        CustomerOrderLineHandler.RequestWrapper req = new CustomerOrderLineHandler.RequestWrapper();
        req.operationType = 'create';
        req.newRecord     = b.orderItem;

        Test.startTest();
        CustomerOrderLineHandler.process(new List<CustomerOrderLineHandler.RequestWrapper>{ req });
        Test.stopTest();

        CustomerOrderLine__c col = [
            SELECT Id, Name, OrderItem__c
            FROM CustomerOrderLine__c
            WHERE OrderItem__c = :b.orderItem.Id
            LIMIT 1
        ];
        Assert.areNotEqual(null, col,                       'COL should be created by invocable entry point');
        Assert.isTrue(col.Name.startsWith('COL-'),          'Name should be formatted via utils');
    }

    @IsTest
    static void testInvocableProcess_nullRequests_noThrow() {
        Test.startTest();
        // If process(null) throws any exception, this test will automatically fail.
        // No assertion needed — reaching this comment without crashing is the test passing.
        CustomerOrderLineHandler.process(null);
        Test.stopTest();
    }
}
