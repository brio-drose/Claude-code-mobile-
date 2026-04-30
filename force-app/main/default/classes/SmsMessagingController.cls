/**
 * Apex controller for the smsMessaging LWC.
 *
 * Expects a custom object SMS_Event__c with fields:
 *   Message_Body__c  (LongTextArea)
 *   Direction__c     (Picklist: Inbound | Outbound)
 *   Status__c        (Picklist: Pending | Sent | Delivered | Failed)
 *   From_Number__c   (Text)
 *   Is_Read__c       (Checkbox)
 *   Contact__c       (Lookup → Contact)
 *   Lead__c          (Lookup → Lead)
 *   Account__c       (Lookup → Account)
 *
 * Adapt the sendSms method to call your SMS provider's API
 * (e.g. Dialpad, Twilio, etc.) via a Named Credential / HttpCallout.
 */
public with sharing class SmsMessagingController {

    private static final Integer MAX_MESSAGES = 200;

    // ── Query SMS history ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<SMS_Event__c> getSmsHistory(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('recordId is required.');
        }

        String objectType = recordId.getSObjectType().getDescribe().getName();
        String filterField = resolveFilterField(objectType);

        if (filterField == null) {
            throw new AuraHandledException(
                'SMS history is not supported for ' + objectType + ' records.'
            );
        }

        String query =
            'SELECT Id, Message_Body__c, Direction__c, Status__c, ' +
            '       From_Number__c, Is_Read__c, CreatedDate ' +
            'FROM SMS_Event__c ' +
            'WHERE ' + filterField + ' = :recordId ' +
            'ORDER BY CreatedDate ASC ' +
            'LIMIT :MAX_MESSAGES';

        return Database.query(query);
    }

    // ── Send an outbound SMS ──────────────────────────────────────────────────

    @AuraEnabled
    public static SMS_Event__c sendSms(Id recordId, String messageBody) {
        if (recordId == null)                              throw new AuraHandledException('recordId is required.');
        if (String.isBlank(messageBody))                  throw new AuraHandledException('Message body cannot be blank.');
        if (messageBody.trim().length() > 1600)           throw new AuraHandledException('Message exceeds 1600 character limit.');

        String objectType  = recordId.getSObjectType().getDescribe().getName();
        String filterField = resolveFilterField(objectType);

        if (filterField == null) {
            throw new AuraHandledException('Cannot send SMS for ' + objectType + ' records.');
        }

        // 1. Dispatch to SMS provider (replace with your callout)
        String providerStatus = dispatchToProvider(recordId, messageBody.trim());

        // 2. Persist the outbound event record
        SMS_Event__c evt = new SMS_Event__c(
            Message_Body__c = messageBody.trim(),
            Direction__c    = 'Outbound',
            Status__c       = providerStatus
        );
        evt.put(filterField, recordId);

        insert evt;
        return evt;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static String resolveFilterField(String objectType) {
        Map<String, String> mapping = new Map<String, String>{
            'Contact' => 'Contact__c',
            'Lead'    => 'Lead__c',
            'Account' => 'Account__c'
        };
        return mapping.get(objectType);
    }

    /**
     * Replace this stub with a real HTTP callout to your SMS provider.
     * Use a Named Credential for auth (e.g. callout:Dialpad_API).
     *
     * Returns the initial delivery status to store on the record.
     */
    private static String dispatchToProvider(Id recordId, String body) {
        // TODO: implement callout to SMS provider
        // Example Dialpad structure (pseudocode):
        //   HttpRequest req = new HttpRequest();
        //   req.setEndpoint('callout:Dialpad_API/v2/sms');
        //   req.setMethod('POST');
        //   req.setHeader('Content-Type', 'application/json');
        //   req.setBody(JSON.serialize(new Map<String,Object>{
        //       'to_number'    => lookupPhoneNumber(recordId),
        //       'text'         => body
        //   }));
        //   Http h = new Http();
        //   HttpResponse res = h.send(req);
        //   if (res.getStatusCode() != 200) throw new AuraHandledException('Provider error: ' + res.getStatus());
        //   return 'Sent';
        return 'Sent';
    }
}
