// ─── CustomerOrderLineServiceTest ────────────────────────────────────────────
/**
 * Unit + integration tests for CustomerOrderLineService.
 *
 * What we test:
 *  - buildCOL()        : field mapping is correct.
 *  - applyChanges()    : only changed fields get written; returns correct boolean.
 *  - buildPseudoOld()  : reconstructs the right field values from a COL.
 *  - handleCreates()   : async future creates COLs for new OrderItems.
 *  - handleUpdates()   : async future updates COLs when OI fields change.
 *  - handleUpdateToDeleted() : synchronously tags COLs as [DEL].
 *
 * Test data setup:
 *  Standard objects (Account, Order, Product2, PricebookEntry, OrderItem) are
 *  created in @testSetup so all test methods share one DML transaction.
 *
 * NOTE: @future methods only execute after Test.stopTest(), so all async
 *       assertions are placed after that call.
 */
@isTest
private class CustomerOrderLineServiceTest {

    // ── TEST DATA SETUP ───────────────────────────────────────────────────────

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Use standard pricebook
        Id pbId = Test.getStandardPricebookId();

        Order ord = new Order(
            AccountId     = acc.Id,
            Status        = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id  = pbId
        );
        insert ord;

        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id   = pbId,
            Product2Id     = prod.Id,
            UnitPrice      = 100,
            IsActive       = true
        );
        insert pbe;

        OrderItem oi = new OrderItem(
            OrderId        = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity       = 1,
            UnitPrice      = 100,
            ServiceDate    = Date.today(),
            EndDate        = Date.today().addMonths(12)
        );
        insert oi;
    }

    // ── HELPER: fetch the test OrderItem ─────────────────────────────────────

    private static OrderItem getTestOI() {
        return [
            SELECT Id, OrderItemNumber, Product2.Name,
                   Order.AccountId, SBQQ__Contract__c, SBQQ__Contract__r.Status,
                   Quantity, TotalPrice, ServiceDate, EndDate,
                   blng__LastChargeToDate__c, blng__NextBillingDate__c,
                   SBQQ__DefaultSubscriptionTerm__c
            FROM   OrderItem
            LIMIT  1
        ];
    }

    // ── buildCOL ──────────────────────────────────────────────────────────────

    @isTest
    static void buildCOL_mapsFieldsCorrectly() {
        OrderItem oi = getTestOI();

        CustomerOrderLine__c col = CustomerOrderLineService.buildCOL(oi);

        System.assertEquals(oi.Id,        col.OrderItem__c,  'OrderItem__c should match');
        System.assertEquals(oi.Quantity,   col.Quantity__c,   'Quantity should match');
        System.assertEquals(oi.TotalPrice, col.Total_Price__c,'TotalPrice should match');
        System.assertNotEquals(null, col.Last_Synced_Date__c, 'Last_Synced_Date__c must be set');
        System.assert(col.Name.startsWith('COL-'),           'Name should start with COL-');
    }

    // ── applyChanges ──────────────────────────────────────────────────────────

    @isTest
    static void applyChanges_noChange_returnsFalse() {
        OrderItem oi  = getTestOI();
        CustomerOrderLine__c col = CustomerOrderLineService.buildCOL(oi);

        // Old and new are identical — nothing should change
        Boolean changed = CustomerOrderLineService.applyChanges(col, oi, oi);
        System.assertEquals(false, changed, 'Identical OIs should produce no change');
    }

    @isTest
    static void applyChanges_quantityChanged_returnsTrue() {
        OrderItem oldOI = getTestOI();
        OrderItem newOI = getTestOI();
        newOI.Quantity  = oldOI.Quantity + 5;

        CustomerOrderLine__c col = CustomerOrderLineService.buildCOL(oldOI);
        Boolean changed = CustomerOrderLineService.applyChanges(col, oldOI, newOI);

        System.assertEquals(true,              changed,       'Changed quantity should flag as changed');
        System.assertEquals(newOI.Quantity,    col.Quantity__c, 'COL Quantity should be updated');
    }

    @isTest
    static void applyChanges_endDateChanged_returnsTrue() {
        OrderItem oldOI = getTestOI();
        OrderItem newOI = getTestOI();
        newOI.EndDate   = oldOI.EndDate.addMonths(6);

        CustomerOrderLine__c col = CustomerOrderLineService.buildCOL(oldOI);
        Boolean changed = CustomerOrderLineService.applyChanges(col, oldOI, newOI);

        System.assertEquals(true,           changed,        'Changed EndDate should flag as changed');
        System.assertEquals(newOI.EndDate,  col.End_Date__c,'COL EndDate should be updated');
    }

    // ── buildPseudoOld ────────────────────────────────────────────────────────

    @isTest
    static void buildPseudoOld_reconstructsFieldsFromCOL() {
        OrderItem oi  = getTestOI();
        CustomerOrderLine__c col = CustomerOrderLineService.buildCOL(oi);

        OrderItem pseudo = CustomerOrderLineService.buildPseudoOld(col);

        System.assertEquals(col.Quantity__c,   pseudo.Quantity,   'Quantity should be reconstructed');
        System.assertEquals(col.End_Date__c,   pseudo.EndDate,    'EndDate should be reconstructed');
        System.assertEquals(col.Total_Price__c, pseudo.TotalPrice, 'TotalPrice should be reconstructed');
    }

    // ── handleCreates (async) ─────────────────────────────────────────────────

    @isTest
    static void handleCreates_insertsCOLForNewOrderItem() {
        OrderItem oi = getTestOI();
        // Ensure no COL exists yet
        System.assertEquals(0, [SELECT COUNT() FROM CustomerOrderLine__c WHERE OrderItem__c = :oi.Id]);

        Test.startTest();
        CustomerOrderLineService.handleCreates(new Set<Id>{ oi.Id });
        Test.stopTest(); // @future runs here

        List<CustomerOrderLine__c> cols = [
            SELECT Id, OrderItem__c FROM CustomerOrderLine__c WHERE OrderItem__c = :oi.Id
        ];
        System.assertEquals(1, cols.size(), 'Exactly one COL should be created');
    }

    @isTest
    static void handleCreates_idempotent_doesNotDuplicateCOL() {
        OrderItem oi = getTestOI();

        // Pre-create a COL manually
        insert CustomerOrderLineService.buildCOL(oi);

        Test.startTest();
        CustomerOrderLineService.handleCreates(new Set<Id>{ oi.Id });
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM CustomerOrderLine__c WHERE OrderItem__c = :oi.Id];
        System.assertEquals(1, count, 'Second call should not create a duplicate COL');
    }

    // ── handleUpdates (async) ─────────────────────────────────────────────────

    @isTest
    static void handleUpdates_updatesCOLWhenOIChanges() {
        OrderItem oi = getTestOI();
        insert CustomerOrderLineService.buildCOL(oi);

        // Change quantity on the OI
        oi.Quantity = 99;
        update oi;

        // Build maps as the handler would receive them
        Map<Id, OrderItem> newMap = new Map<Id, OrderItem>{ oi.Id => oi };
        Map<Id, OrderItem> oldMap = new Map<Id, OrderItem>{ oi.Id => getTestOI() }; // stale copy

        Test.startTest();
        CustomerOrderLineService.handleUpdates(newMap, oldMap);
        Test.stopTest();

        CustomerOrderLine__c updated = [
            SELECT Quantity__c FROM CustomerOrderLine__c WHERE OrderItem__c = :oi.Id
        ];
        System.assertEquals(99, updated.Quantity__c, 'COL Quantity should reflect OI change');
    }

    // ── handleUpdateToDeleted (sync) ──────────────────────────────────────────

    @isTest
    static void handleUpdateToDeleted_prependsDelTag() {
        OrderItem oi = getTestOI();
        CustomerOrderLine__c col = CustomerOrderLineService.buildCOL(oi);
        insert col;

        // Simulate delete by calling the method directly with the OI
        Test.startTest();
        CustomerOrderLineService.handleUpdateToDeleted(new List<OrderItem>{ oi });
        Test.stopTest();

        CustomerOrderLine__c tagged = [
            SELECT Name, Last_Synced_Date__c FROM CustomerOrderLine__c WHERE Id = :col.Id
        ];
        System.assert(tagged.Name.startsWith('[DEL]'),     'Name should start with [DEL]');
        System.assertNotEquals(null, tagged.Last_Synced_Date__c, 'Last_Synced_Date__c should be stamped');
    }

    @isTest
    static void handleUpdateToDeleted_alreadyTagged_noDoubleTag() {
        OrderItem oi = getTestOI();
        CustomerOrderLine__c col = CustomerOrderLineService.buildCOL(oi);
        col.Name = '[DEL] COL-Existing';
        insert col;

        Test.startTest();
        CustomerOrderLineService.handleUpdateToDeleted(new List<OrderItem>{ oi });
        Test.stopTest();

        CustomerOrderLine__c tagged = [SELECT Name FROM CustomerOrderLine__c WHERE Id = :col.Id];
        System.assert(!tagged.Name.startsWith('[DEL] [DEL]'), 'Should not double-tag an already-tagged COL');
    }
}
