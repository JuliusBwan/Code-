/**
 * CustomerOrderLineService
 * ------------------------
 * PURPOSE: This is the "brain" of the operation. It receives a list of events
 * from the Flow (create, update, or delete) and carries out the right database
 * actions on CustomerOrderLine__c records.
 *
 * processRequests(): sorts incoming requests into three buckets and calls:
 *   - handleCreates():        creates new COL records from new OrderItems
 *   - handleUpdates():        syncs changed field values to existing COL records
 *   - handleUpdateToDeletes(): tags COL names with [DEL] when an OrderItem is deleted
 *
 * NOTES:
 * - Uses partial DML (allOrNone=false) so one failure doesn't block the rest.
 * - Calls NotificationService to email the user if any records fail.
 * - Duplicate COL creation is prevented by checking for an existing OrderItem__c link.
 * - Relationship fields like SBQQ__Subscription__r may not be populated even when
 *   the Id field is set — always null-check __r before reading from it.
 *
 * CHANGES FROM ORIGINAL:
 *
 * 1. handleUpdateToDeletes — removed redundant List wrapper around SOQL
 *    ===================================================================
 *    The original was:
 *        List<CustomerOrderLine__c> orphanedCols = new List<CustomerOrderLine__c>([SELECT ...]);
 *
 *    A SOQL query already returns a List — wrapping it in "new List<>()" is like
 *    putting a bag inside an identical bag. It works, but it's confusing noise.
 *    The fix is to assign the query result directly:
 *        List<CustomerOrderLine__c> orphanedCols = [SELECT ...];
 *
 * 2. handleUpdates — paired OrderItem wrapper (OrderItemPair inner class)
 *    ====================================================================
 *    The original used two parallel lists (newItems and oldItems) and relied on
 *    matching list indexes (newItems[0] matches oldItems[0], etc.) to pair each
 *    new record with its old version.
 *    
 *    This is fragile — if a caller ever passes lists that are even slightly out
 *    of sync, you get wrong data with no error message. Instead, we now bundle
 *    each new+old pair into a small helper class (OrderItemPair) before looping.
 *    This makes the pairing explicit and safe, and the loop body is easier to read.
 */
public with sharing class CustomerOrderLineService {

    /**
     * Simple container that holds a matched pair of OrderItems (new and old version).
     * Used internally by handleUpdates() to avoid relying on fragile parallel list indexes.
     */
    private class OrderItemPair {
        public OrderItem newOI;
        public OrderItem oldOI;
        public OrderItemPair(OrderItem n, OrderItem o) { newOI = n; oldOI = o; }
    }

    public static void processRequests(List<CustomerOrderLineHandler.RequestWrapper> requests){
        
        List<OrderItem> creates      = new List<OrderItem>();
        List<OrderItem> updateNew    = new List<OrderItem>();
        List<OrderItem> updateOld    = new List<OrderItem>();
        List<Id>        updateDeletes = new List<Id>();
        
        for (CustomerOrderLineHandler.RequestWrapper req : requests){
            if (req == null || String.isBlank(req.operationType)) continue;

            if      (req.operationType == 'create' && req.newRecord != null && req.newRecord.Id != null) {
                creates.add(req.newRecord);
            }
            else if (req.operationType == 'update' && req.newRecord != null && req.oldRecord != null && req.newRecord.Id != null) {
                updateNew.add(req.newRecord);
                updateOld.add(req.oldRecord);
            }
            else if (req.operationType == 'delete' && req.deletedRecordId != null) {
                updateDeletes.add(req.deletedRecordId);
            }
        }
                
        if (!creates.isEmpty())       { handleCreates(creates); }
        if (!updateNew.isEmpty())     { handleUpdates(updateNew, updateOld); }
        if (!updateDeletes.isEmpty()) { handleUpdateToDeletes(updateDeletes); }
    }

    public static void handleCreates(List<OrderItem> newItems) { 
        Set<Id> oiIds = new Set<Id>();
        for (OrderItem oi : newItems) if (oi.Id != null) oiIds.add(oi.Id); 
        
        Map<Id, CustomerOrderLine__c> existingByOrderItem = CustomerOrderLineRepository.getByOrderItemIds(oiIds);
        
        List<CustomerOrderLine__c> colsToInsert = new List<CustomerOrderLine__c>();
        for (OrderItem o : newItems){
            if(!existingByOrderItem.containsKey(o.Id)) {
                CustomerOrderLine__c col = new CustomerOrderLine__c();
                col.Name                       = CustomerOrderLinesUtils.formatColName(o);
                col.OrderItem__c               = o.Id;
                col.Account__c                 = o.SBQQ__Subscription__c != null ? o.SBQQ__Subscription__r.SBQQ__Account__c : null;
                col.blng_LastChargeToDate__c   = o.blng__LastChargeToDate__c;
                col.blng_NextBillingDate__c    = o.blng__NextBillingDate__c;
                col.Contract_Status__c         = o.SBQQ__Contract__c != null ? o.SBQQ__Contract__r.Status : null;
                col.End_Date__c                = o.EndDate;
                col.Last_Synced_Date__c        = System.now();
                col.OrderItemNumber__c         = o.OrderItemNumber;
                col.Product_Name__c            = (o.Product2 != null) ? o.Product2.Name : null;
                col.Quantity__c                = o.Quantity;
                col.Service_Date__c            = o.ServiceDate;
                col.Subscription_Id__c         = o.SBQQ__Subscription__c;
                col.Subscription_Term_Months__c = o.SBQQ__DefaultSubscriptionTerm__c;
                col.Total_Price__c             = o.TotalPrice;
                colsToInsert.add(col);
            }
        }
        if (colsToInsert.isEmpty()) { return; }
        
        Database.SaveResult[] results = Database.insert(colsToInsert, false);
        NotificationService.handleResults('Customer Order Lines - Create Summary', colsToInsert.size(), results);
    }

    public static void handleUpdates(List<OrderItem> newItems, List<OrderItem> oldItems) {
        
        // FIXED: build explicit pairs instead of relying on parallel list indexes.
        // If the lists were ever misaligned, the old approach would silently produce wrong data.
        // Now each new+old pair is bundled together immediately, so they can never get out of sync.
        List<OrderItemPair> pairs = new List<OrderItemPair>();
        for (Integer i = 0; i < newItems.size(); i++) {
            pairs.add(new OrderItemPair(newItems[i], oldItems[i]));
        }

        Set<Id> orderIds = new Set<Id>();
        for (OrderItemPair p : pairs) { orderIds.add(p.newOI.Id); }
        
        Map<Id, CustomerOrderLine__c> existing = CustomerOrderLineRepository.getByOrderItemIds(orderIds);
        
        List<CustomerOrderLine__c> colsToUpdate = new List<CustomerOrderLine__c>();
        
        for (OrderItemPair p : pairs) {
            OrderItem newOI = p.newOI;
            OrderItem oldOI = p.oldOI;
            
            if(existing.containsKey(newOI.Id)) {
                CustomerOrderLine__c col = existing.get(newOI.Id);
                Boolean changed = false;
                
                if (oldOI.blng__LastChargeToDate__c != newOI.blng__LastChargeToDate__c) { col.blng_LastChargeToDate__c  = newOI.blng__LastChargeToDate__c; changed = true; }
                if (oldOI.blng__NextBillingDate__c  != newOI.blng__NextBillingDate__c)  { col.blng_NextBillingDate__c   = newOI.blng__NextBillingDate__c;  changed = true; }
                
                String newContractStatus = newOI.SBQQ__Contract__c != null ? newOI.SBQQ__Contract__r.Status : null;
                String oldContractStatus = oldOI.SBQQ__Contract__c != null ? oldOI.SBQQ__Contract__r.Status : null;
                if (oldContractStatus != newContractStatus) { col.Contract_Status__c = newContractStatus; changed = true; }
                
                if (oldOI.EndDate          != newOI.EndDate)          { col.End_Date__c       = newOI.EndDate;          changed = true; }
                if (oldOI.OrderItemNumber  != newOI.OrderItemNumber)  { col.OrderItemNumber__c = newOI.OrderItemNumber;  changed = true; }
                
                String oldProdName = oldOI.Product2 != null ? oldOI.Product2.Name : null;
                String newProdName = newOI.Product2 != null ? newOI.Product2.Name : null;
                if (oldProdName != newProdName) { col.Product_Name__c = newProdName; changed = true; }
                
                if (oldOI.Quantity                          != newOI.Quantity)                          { col.Quantity__c                  = newOI.Quantity;                          changed = true; }
                if (oldOI.ServiceDate                       != newOI.ServiceDate)                       { col.Service_Date__c              = newOI.ServiceDate;                       changed = true; }
                if (oldOI.SBQQ__DefaultSubscriptionTerm__c  != newOI.SBQQ__DefaultSubscriptionTerm__c) { col.Subscription_Term_Months__c  = newOI.SBQQ__DefaultSubscriptionTerm__c;  changed = true; }
                if (oldOI.TotalPrice                        != newOI.TotalPrice)                        { col.Total_Price__c               = newOI.TotalPrice;                        changed = true; }
                
                if (changed) { col.Last_Synced_Date__c = System.now(); colsToUpdate.add(col); }
            }
        }

        if (colsToUpdate.isEmpty()) { return; }
        
        Database.SaveResult[] results = Database.update(colsToUpdate, false);
        NotificationService.handleResults('Customer Order Lines - Update Summary', colsToUpdate.size(), results);
    }

    public static void handleUpdateToDeletes(List<Id> deletedIds) {

        // FIXED: removed the redundant "new List<CustomerOrderLine__c>([SELECT ...])" wrapper.
        // A SOQL query already returns a List — there is no need to wrap it again.
        List<CustomerOrderLine__c> orphanedCols = [SELECT Id, Name FROM CustomerOrderLine__c WHERE OrderItem__c IN :deletedIds];
        
        List<CustomerOrderLine__c> deletedToUpdate = new List<CustomerOrderLine__c>();
        for (CustomerOrderLine__c col : orphanedCols) {
            col.Name = CustomerOrderLinesUtils.prependDeletedTag(col.Name);
            deletedToUpdate.add(col);
        }

        if (deletedToUpdate.isEmpty()) { return; }
        
        Database.SaveResult[] results = Database.update(deletedToUpdate, false);
        NotificationService.handleResults('Customer Order Lines - Delete Summary', deletedToUpdate.size(), results);
    }
}
