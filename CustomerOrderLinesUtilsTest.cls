// ─── CustomerOrderLinesUtilsTest ──────────────────────────────────────────────
@isTest
private class CustomerOrderLinesUtilsTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Utils Test Account');
        insert acc;

        Id pbId = Test.getStandardPricebookId();

        Order ord = new Order(
            AccountId     = acc.Id,
            Status        = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id  = pbId
        );
        insert ord;

        Product2 prod = new Product2(Name = 'Utils Product', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pbId,
            Product2Id   = prod.Id,
            UnitPrice    = 100,
            IsActive     = true
        );
        insert pbe;

        OrderItem oi = new OrderItem(
            OrderId          = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 100,
            ServiceDate      = Date.today(),
            EndDate          = Date.today().addMonths(12)
        );
        insert oi;
    }

    // ── prependDeletedTag ─────────────────────────────────────────────────────

    @isTest
    static void prependDeletedTag_nullInput_returnsDelOnly() {
        System.assertEquals('[DEL]', CustomerOrderLinesUtils.prependDeletedTag(null),
            'Null name should return bare [DEL]');
    }

    @isTest
    static void prependDeletedTag_blankInput_returnsDelOnly() {
        System.assertEquals('[DEL]', CustomerOrderLinesUtils.prependDeletedTag('   '),
            'Blank name should return bare [DEL]');
    }

    @isTest
    static void prependDeletedTag_alreadyTagged_returnsUnchanged() {
        String input = '[DEL] COL-12345';
        System.assertEquals(input, CustomerOrderLinesUtils.prependDeletedTag(input),
            'Already-tagged name should not be double-tagged');
    }

    @isTest
    static void prependDeletedTag_normalName_prependsTag() {
        System.assertEquals('[DEL] COL-12345',
            CustomerOrderLinesUtils.prependDeletedTag('COL-12345'),
            'Normal name should get [DEL] prefix');
    }

    // ── formatColName ─────────────────────────────────────────────────────────

    @isTest
    static void formatColName_withOrderItemNumber_usesOnlyKey() {
        OrderItem oi = [
            SELECT Id, OrderItemNumber, Product2.Name
            FROM   OrderItem
            LIMIT  1
        ];

        String result = CustomerOrderLinesUtils.formatColName(oi);

        System.assert(result.startsWith('COL-'),
            'Name should start with COL-');
        System.assert(result.contains(oi.OrderItemNumber),
            'Name should contain the OrderItemNumber');
        System.assert(!result.contains(oi.Product2.Name),
            'Name should not include the product name');
        System.assert(result.length() <= 80,
            'Name should fit within the 80-char limit');
    }

    @isTest
    static void formatColName_withoutProduct_stillFormatsCorrectly() {
        OrderItem oi = [
            SELECT Id, OrderItemNumber
            FROM   OrderItem
            LIMIT  1
        ];

        String result = CustomerOrderLinesUtils.formatColName(oi);

        System.assert(result.startsWith('COL-'),
            'Name should start with COL-');
        System.assert(result.contains(oi.OrderItemNumber),
            'Name should contain the OrderItemNumber');
    }
}
