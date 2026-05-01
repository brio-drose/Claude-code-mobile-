/**
 * Apex controller for the smsMessaging LWC.
 *
 * SMS_Event__c expected fields:
 *   Message_Body__c  (LongTextArea)
 *   Direction__c     (Picklist: Inbound | Outbound)
 *   Status__c        (Picklist: Pending | Sent | Delivered | Failed)
 *   From_Number__c   (Text)
 *   Is_Read__c       (Checkbox)
 *   Account__c       (Lookup → Account)
 *   Intake__c        (Lookup → Intake__c)
 *   Matter__c        (Lookup → Matter__c)
 *
 * Intake__c and Matter__c must each have an Account__c lookup field.
 */
public with sharing class SmsMessagingController {

    private static final Integer MAX_MESSAGES = 200;

    // ── Get SMS history ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<SmsMessageWrapper> getSmsHistory(Id recordId, Boolean showAll) {
        if (recordId == null) throw new AuraHandledException('recordId is required.');

        String objectType = recordId.getSObjectType().getDescribe().getName();
        Boolean isAccountPage = objectType == 'Account';

        List<SMS_Event__c> records;

        if (isAccountPage || showAll == true) {
            Id accountId = isAccountPage ? recordId : resolveAccountId(recordId, objectType);
            records = queryByAccount(accountId);
        } else {
            records = queryByRecord(recordId, objectType);
        }

        return buildWrappers(records, recordId, isAccountPage);
    }

    // ── Send an outbound SMS ──────────────────────────────────────────────────

    @AuraEnabled
    public static SmsMessageWrapper sendSms(Id recordId, String messageBody) {
        if (recordId == null)                   throw new AuraHandledException('recordId is required.');
        if (String.isBlank(messageBody))        throw new AuraHandledException('Message body cannot be blank.');
        if (messageBody.trim().length() > 1600) throw new AuraHandledException('Message exceeds 1600 character limit.');

        String objectType  = recordId.getSObjectType().getDescribe().getName();
        String filterField = resolveFilterField(objectType);
        if (filterField == null) throw new AuraHandledException('Cannot send SMS for ' + objectType + ' records.');

        String providerStatus = dispatchToProvider(recordId, messageBody.trim());

        SMS_Event__c evt = new SMS_Event__c(
            Message_Body__c = messageBody.trim(),
            Direction__c    = 'Outbound',
            Status__c       = providerStatus
        );

        // Always associate with the account as well
        if (objectType != 'Account') {
            Id accountId = resolveAccountId(recordId, objectType);
            evt.Account__c = accountId;
        }
        evt.put(filterField, recordId);

        insert evt;

        // Re-query to pick up CreatedDate and relationship names
        List<SMS_Event__c> inserted = queryById(evt.Id);
        List<SmsMessageWrapper> wrappers = buildWrappers(inserted, recordId, objectType == 'Account');
        return wrappers.isEmpty() ? null : wrappers[0];
    }

    // ── Queries ───────────────────────────────────────────────────────────────

    private static List<SMS_Event__c> queryByAccount(Id accountId) {
        return [
            SELECT Id, Message_Body__c, Direction__c, Status__c,
                   From_Number__c, Is_Read__c, CreatedDate,
                   Account__c, Account__r.Name,
                   Intake__c,  Intake__r.Name,
                   Matter__c,  Matter__r.Name
            FROM   SMS_Event__c
            WHERE  Account__c = :accountId
            ORDER BY CreatedDate ASC
            LIMIT  :MAX_MESSAGES
        ];
    }

    private static List<SMS_Event__c> queryByRecord(Id recordId, String objectType) {
        String filterField = resolveFilterField(objectType);
        if (filterField == null) throw new AuraHandledException('Unsupported object: ' + objectType);

        String q =
            'SELECT Id, Message_Body__c, Direction__c, Status__c, ' +
            '       From_Number__c, Is_Read__c, CreatedDate, ' +
            '       Account__c, Account__r.Name, ' +
            '       Intake__c,  Intake__r.Name, ' +
            '       Matter__c,  Matter__r.Name ' +
            'FROM SMS_Event__c ' +
            'WHERE ' + filterField + ' = :recordId ' +
            'ORDER BY CreatedDate ASC ' +
            'LIMIT :MAX_MESSAGES';
        return Database.query(q);
    }

    private static List<SMS_Event__c> queryById(Id smsId) {
        return [
            SELECT Id, Message_Body__c, Direction__c, Status__c,
                   From_Number__c, Is_Read__c, CreatedDate,
                   Account__c, Account__r.Name,
                   Intake__c,  Intake__r.Name,
                   Matter__c,  Matter__r.Name
            FROM   SMS_Event__c
            WHERE  Id = :smsId
            LIMIT  1
        ];
    }

    // ── Wrapper builder ───────────────────────────────────────────────────────

    private static List<SmsMessageWrapper> buildWrappers(
        List<SMS_Event__c> records, Id currentRecordId, Boolean isAccountPage
    ) {
        List<SmsMessageWrapper> results = new List<SmsMessageWrapper>();
        for (SMS_Event__c r : records) {
            SmsMessageWrapper w = new SmsMessageWrapper();
            w.id          = r.Id;
            w.messageBody = r.Message_Body__c;
            w.direction   = r.Direction__c;
            w.status      = r.Status__c;
            w.fromNumber  = r.From_Number__c;
            w.isRead      = r.Is_Read__c;
            w.createdDate = String.valueOf(r.CreatedDate);

            if (isAccountPage) {
                w.isCrossRecord      = false;
                w.relatedRecordName  = null;
                w.relatedRecordId    = null;
            } else {
                Boolean belongsToCurrent =
                    (r.Intake__c != null && r.Intake__c == currentRecordId) ||
                    (r.Matter__c != null && r.Matter__c == currentRecordId);

                w.isCrossRecord = !belongsToCurrent;

                if (w.isCrossRecord) {
                    if (r.Intake__c != null && r.Intake__c != currentRecordId) {
                        w.relatedRecordName = r.Intake__r?.Name;
                        w.relatedRecordId   = r.Intake__c;
                    } else if (r.Matter__c != null && r.Matter__c != currentRecordId) {
                        w.relatedRecordName = r.Matter__r?.Name;
                        w.relatedRecordId   = r.Matter__c;
                    } else {
                        // Account-level message (no intake or matter)
                        w.relatedRecordName = r.Account__r?.Name;
                        w.relatedRecordId   = r.Account__c;
                    }
                }
            }
            results.add(w);
        }
        return results;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Id resolveAccountId(Id recordId, String objectType) {
        String q = 'SELECT Account__c FROM ' + objectType + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> recs = Database.query(q);
        if (recs.isEmpty()) throw new AuraHandledException('Record not found: ' + recordId);
        Id accountId = (Id) recs[0].get('Account__c');
        if (accountId == null) throw new AuraHandledException('No account linked to this record.');
        return accountId;
    }

    private static String resolveFilterField(String objectType) {
        Map<String, String> mapping = new Map<String, String>{
            'Account'   => 'Account__c',
            'Intake__c' => 'Intake__c',
            'Matter__c' => 'Matter__c'
        };
        return mapping.get(objectType);
    }

    /**
     * Replace with a real HTTP callout to your SMS provider.
     * Use a Named Credential for authentication (e.g. callout:Dialpad_API).
     */
    private static String dispatchToProvider(Id recordId, String body) {
        // TODO: implement callout
        return 'Sent';
    }

    // ── Wrapper class ─────────────────────────────────────────────────────────

    public class SmsMessageWrapper {
        @AuraEnabled public String  id;
        @AuraEnabled public String  messageBody;
        @AuraEnabled public String  direction;
        @AuraEnabled public String  status;
        @AuraEnabled public String  fromNumber;
        @AuraEnabled public Boolean isRead;
        @AuraEnabled public String  createdDate;
        @AuraEnabled public Boolean isCrossRecord;
        @AuraEnabled public String  relatedRecordName;
        @AuraEnabled public String  relatedRecordId;
    }
}
