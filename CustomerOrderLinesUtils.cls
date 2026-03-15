/**
 * CustomerOrderLinesUtils
 * -----------------------
 * PURPOSE: A small bag of helper/utility methods used by the service layer.
 * These are pure functions — they take inputs and return outputs with no
 * side effects like database writes or emails.
 *
 * prependDeletedTag(String):
 *   Adds "[DEL]" to the front of a record name when an OrderItem is deleted,
 *   so it's obvious in the UI that the related order item no longer exists.
 *   Safe to call multiple times — it won't double-tag a name that already has [DEL].
 *
 * formatColName(OrderItem):
 *   Builds a consistent, readable name for a new CustomerOrderLine__c record
 *   based on the OrderItem's number and product name.
 *
 * CHANGES FROM ORIGINAL:
 * - No changes to this class itself. The bugs were only in the test file (see below).
 */
public with sharing class CustomerOrderLinesUtils {
    
    public static String prependDeletedTag(String originalName) {
        if (originalName == null || String.isBlank(originalName)) { return '[DEL]'; }
        if (originalName.startsWith('[DEL]')) { return originalName; }
        return '[DEL] ' + originalName;
    }

    public static String formatColName(OrderItem o){
        String key = (o.OrderItemNumber != null) ? o.OrderItemNumber : String.valueOf(o.Id);
        String prod = (o.Product2 != null && o.Product2.Name != null) ? '-' + o.Product2.Name : '';
        return 'COL-' + key + prod;
    }
}
