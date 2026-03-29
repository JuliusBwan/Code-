// ─── CustomerOrderLinesUtilsTest ──────────────────────────────────────────────
/**
 * Tests for CustomerOrderLinesUtils.
 *
 * Pure unit tests — no DML needed for prependDeletedTag.
 * formatColName tests DO need a real insert so Salesforce auto-generates
 * OrderItemNumber (it is a read-only system field and cannot be set manually).
 */
@isTest
private class CustomerOrderLinesUtilsTest {

    // ── TEST DATA ─────────────────────────────────────────────────────────────

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

        // Insert two OrderItems:
        //  - one with a Product (so formatColName includes the product suffix)
        //  - one without (covers the no-product branch) — achieved by querying
        //    without the Product2 relationship in that specific test
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

    // ── prependDeletedTag — pure unit tests (no DML needed) ───────────────────

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

    // ── formatColName — requires a real insert for OrderItemNumber ────────────

    @isTest
    static void formatColName_withOrderItemNumberAndProduct_includesBoth() {
        // Query WITH Product2 so the relationship is populated
        OrderItem oi = [
            SELECT Id, OrderItemNumber, Product2.Name
            FROM   OrderItem
            LIMIT  1
        ];

        String result = CustomerOrderLinesUtils.formatColName(oi);

        // OrderItemNumber is system-generated (e.g. "00000001") — we assert structure
        // rather than an exact value because the number varies per org
        System.assert(result.startsWith('COL-'),
            'Name should always start with COL-');
        System.assert(result.contains(oi.OrderItemNumber),
            'Name should contain the auto-generated OrderItemNumber');
        System.assert(result.contains(oi.Product2.Name),
            'Name should contain the product name when Product2 is present');
    }

    @isTest
    static void formatColName_withoutProduct_omitsProductSuffix() {
        // Query WITHOUT Product2 relationship — Product2 will be null on the SObject
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
        System.assert(!result.contains('-Utils Product'),
            'Name should NOT contain a product suffix when Product2 is not queried');
    }
}
