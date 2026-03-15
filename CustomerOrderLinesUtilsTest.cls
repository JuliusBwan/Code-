/**
 * CustomerOrderLinesUtilsTest
 * ---------------------------
 * PURPOSE: Tests that the utility helper methods return the correct output
 * for a range of inputs, including edge cases like null and blank strings.
 *
 * CHANGES FROM ORIGINAL:
 *
 * 1. testFormatColName_usesOrderItemNumberAndProduct — Assert.areEqual → Assert.isTrue
 *    ==================================================================================
 *    The original code was:
 *        Assert.areEqual(formatted.startsWith('COL-'), 'Should start with COL-');
 *        Assert.areEqual(formatted.contains(oi.OrderItemNumber), 'Should include OrderItemNumber');
 *        Assert.areEqual(formatted.contains(oi.Product2.Name), 'Should include Product name');
 *
 *    Each of these expressions (formatted.startsWith(...), formatted.contains(...)) returns
 *    true or false. Assert.areEqual() needs three arguments: (expected, actual, message).
 *    By only passing two arguments here, Salesforce treats true/false as the "expected"
 *    value and the message string as the "actual" value — they are never equal to each
 *    other, so the assertion always passes no matter what. The tests were completely broken.
 *
 *    The fix: use Assert.isTrue() which is the right tool when you're checking a
 *    true/false condition. It takes the condition as argument one and a message as
 *    argument two.
 */
@IsTest
public with sharing class CustomerOrderLinesUtilsTest {
    
    @IsTest
    static void testPrependDeletedTag(){ 
        System.assertEquals('[DEL]',        CustomerOrderLinesUtils.prependDeletedTag(null));
        System.assertEquals('[DEL]',        CustomerOrderLinesUtils.prependDeletedTag(''));
        System.assertEquals('[DEL] Name',   CustomerOrderLinesUtils.prependDeletedTag('Name'));
        System.assertEquals('[DEL] Already',CustomerOrderLinesUtils.prependDeletedTag('[DEL] Already'));
    }

    @IsTest
    static void testFormatColName_usesOrderItemNumberAndProduct() {
        CustomerOrderLineTestDataFactory.OrderBundle b = CustomerOrderLineTestDataFactory.createOrderWithItem();

        OrderItem oi = [SELECT Id, OrderItemNumber, Product2.Name FROM OrderItem WHERE Id = :b.orderItem.Id LIMIT 1];

        String formatted = CustomerOrderLinesUtils.formatColName(oi);

        // FIXED: was Assert.areEqual(formatted.startsWith('COL-'), 'message') — always passed vacuously.
        // Now uses Assert.isTrue() which actually verifies the condition is true.
        Assert.isTrue(formatted.startsWith('COL-'),              'Should start with COL-');
        Assert.isTrue(formatted.contains(oi.OrderItemNumber),    'Should include OrderItemNumber');
        Assert.isTrue(formatted.contains(oi.Product2.Name),      'Should include Product name when available');
    }
}
