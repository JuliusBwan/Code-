/**
 * CustomerOrderLineHandler
 * ------------------------
 * PURPOSE: This is the front door. Salesforce Flows can only call Apex through
 * an @InvocableMethod. This class exposes that single entry point and passes
 * the data straight through to the service layer where the real work happens.
 *
 * RequestWrapper:
 *   A container class used to carry data from the Flow into Apex.
 *   Because each operation (create / update / delete) needs different data,
 *   the wrapper holds all possible fields and the Flow populates whichever
 *   ones apply.
 *
 * NOTES:
 * - Salesforce only allows one @InvocableMethod per class.
 * - For 'create', newRecord must carry a persisted Id (called after insert).
 * - For 'update', both newRecord and oldRecord must be provided and index-aligned.
 * - For 'delete', deletedRecordId is used.
 *
 * CHANGES FROM ORIGINAL:
 * - No changes to this class itself. The bugs were only in the test file (see below).
 */
public class CustomerOrderLineHandler {

    public class RequestWrapper {
        @InvocableVariable(required=true)
        public String operationType;
        // "create", "update", or "delete"
        
        @InvocableVariable
        public OrderItem newRecord;
        // Used for Create or Update operations
        
        @InvocableVariable
        public OrderItem oldRecord;
        // Only used for Update operations

        @InvocableVariable
        public Id deletedRecordId;
        // Used for Delete operations
    }
    
    @InvocableMethod(label='Process OrderItem Event')
    public static void process(List<CustomerOrderLineHandler.RequestWrapper> requests){  
        if (requests == null) { return; }
        CustomerOrderLineService.processRequests(requests);
    }
}
