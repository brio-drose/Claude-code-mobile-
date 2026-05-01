/**
 * Apex controller for the smsMessaging LWC.
 * Reads from Dialpad_SMS_Event__c and sends via DialpadSMSSender.
 *
 * Dialpad_SMS_Event__c relationship fields used here:
 *   Party__c    → Account lookup
 *   Intake__c   → Intake lookup
 *   Matter__c   → Matter lookup
 *
 * litify_pm__Intake__c and litify_pm__Matter__c records reference their
 * parent Account via the litify_pm__Client__c lookup field.
 */
public with sharing class SmsMessagingController {

    private static final Integer MAX_MESSAGES = 200;

    // ── Get SMS history ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<SmsMessageWrapper> getSmsHistory(Id recordId, Boolean showAll) {
        if (recordId == null) throw new AuraHandledException('recordId is required.');

        String objectType   = recordId.getSObjectType().getDescribe().getName();
        Boolean isAccountPage = objectType == 'Account';

        List<Dialpad_SMS_Event__c> records;

        if (isAccountPage || showAll == true) {
            Id accountId = isAccountPage ? recordId : resolveAccountId(recordId, objectType);
            records = queryByAccount(accountId);
        } else {
            records = queryByRecord(recordId, objectType);
        }

        return buildWrappers(records, recordId, isAccountPage);
    }

    // ── Send an outbound SMS via Dialpad ──────────────────────────────────────

    @AuraEnabled
    public static SmsMessageWrapper sendSms(
        Id recordId, String messageBody, String toNumber, String fromNumber
    ) {
        if (recordId == null)                   throw new AuraHandledException('recordId is required.');
        if (String.isBlank(messageBody))        throw new AuraHandledException('Message cannot be blank.');
        if (String.isBlank(toNumber))           throw new AuraHandledException('Recipient phone number is required.');
        if (String.isBlank(fromNumber))         throw new AuraHandledException('From phone number is required.');
        if (messageBody.trim().length() > 1600) throw new AuraHandledException('Message exceeds 1600 characters.');

        String objectType = recordId.getSObjectType().getDescribe().getName();

        // Dispatch via Dialpad
        DialpadSMSSender.SendSMSRequest req = new DialpadSMSSender.SendSMSRequest();
        req.messageText = messageBody.trim();
        req.toNumbers   = new List<String>{ toNumber };
        req.fromNumber  = fromNumber;

        List<DialpadSMSSender.SendSMSResponse> responses =
            DialpadSMSSender.sendSMS(new List<DialpadSMSSender.SendSMSRequest>{ req });
        DialpadSMSSender.SendSMSResponse resp = responses[0];

        if (!resp.success) {
            throw new AuraHandledException(resp.message);
        }

        // Persist the outbound event record
        Dialpad_SMS_Event__c evt = new Dialpad_SMS_Event__c(
            text__c           = messageBody.trim(),
            direction__c      = 'outbound',
            message_status__c = 'sent',
            from_number__c    = fromNumber,
            to_number__c      = toNumber,
            id__c             = resp.smsId
        );

        String filterField = resolveFilterField(objectType);
        if (filterField != null) evt.put(filterField, recordId);

        if (objectType == 'Account') {
            evt.Party__c = recordId;
        } else {
            try {
                evt.Party__c = resolveAccountId(recordId, objectType);
            } catch (Exception e) {
                // Non-fatal: save without account link if lookup fails
            }
        }

        insert evt;

        List<Dialpad_SMS_Event__c> inserted = queryById(evt.Id);
        List<SmsMessageWrapper> wrappers = buildWrappers(inserted, recordId, objectType == 'Account');
        return wrappers.isEmpty() ? null : wrappers[0];
    }

    // ── Queries ───────────────────────────────────────────────────────────────

    private static List<Dialpad_SMS_Event__c> queryByAccount(Id accountId) {
        return [
            SELECT Id, text__c, direction__c, message_status__c,
                   from_number__c, to_number__c,
                   contact_name__c, contact_phone_number__c,
                   CreatedDate, event_timestamp__c,
                   Party__c,  Party__r.Name,
                   Intake__c, Intake__r.Name,
                   Matter__c, Matter__r.Name
            FROM   Dialpad_SMS_Event__c
            WHERE  Party__c = :accountId
            ORDER BY CreatedDate ASC
            LIMIT  :MAX_MESSAGES
        ];
    }

    private static List<Dialpad_SMS_Event__c> queryByRecord(Id recordId, String objectType) {
        String filterField = resolveFilterField(objectType);
        if (filterField == null) throw new AuraHandledException('Unsupported object: ' + objectType);

        String q =
            'SELECT Id, text__c, direction__c, message_status__c, ' +
            '       from_number__c, to_number__c, ' +
            '       contact_name__c, contact_phone_number__c, ' +
            '       CreatedDate, event_timestamp__c, ' +
            '       Party__c, Party__r.Name, ' +
            '       Intake__c, Intake__r.Name, ' +
            '       Matter__c, Matter__r.Name ' +
            'FROM Dialpad_SMS_Event__c ' +
            'WHERE ' + filterField + ' = :recordId ' +
            'ORDER BY CreatedDate ASC ' +
            'LIMIT :MAX_MESSAGES';
        return Database.query(q);
    }

    private static List<Dialpad_SMS_Event__c> queryById(Id smsId) {
        return [
            SELECT Id, text__c, direction__c, message_status__c,
                   from_number__c, to_number__c,
                   contact_name__c, contact_phone_number__c,
                   CreatedDate, event_timestamp__c,
                   Party__c,  Party__r.Name,
                   Intake__c, Intake__r.Name,
                   Matter__c, Matter__r.Name
            FROM   Dialpad_SMS_Event__c
            WHERE  Id = :smsId
            LIMIT  1
        ];
    }

    // ── Wrapper builder ───────────────────────────────────────────────────────

    private static List<SmsMessageWrapper> buildWrappers(
        List<Dialpad_SMS_Event__c> records, Id currentRecordId, Boolean isAccountPage
    ) {
        List<SmsMessageWrapper> results = new List<SmsMessageWrapper>();
        for (Dialpad_SMS_Event__c r : records) {
            SmsMessageWrapper w = new SmsMessageWrapper();
            w.id              = r.Id;
            w.messageBody     = r.text__c;
            w.direction       = r.direction__c;
            w.status          = r.message_status__c;
            w.fromNumber      = r.from_number__c;
            w.toNumber        = r.to_number__c;
            w.contactName     = r.contact_name__c;
            w.contactPhone    = r.contact_phone_number__c;
            w.createdDate     = String.valueOf(r.CreatedDate);

            if (isAccountPage) {
                w.isCrossRecord     = false;
                w.relatedRecordName = null;
                w.relatedRecordId   = null;
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
                        w.relatedRecordName = r.Party__r?.Name;
                        w.relatedRecordId   = r.Party__c;
                    }
                }
            }
            results.add(w);
        }
        return results;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Id resolveAccountId(Id recordId, String objectType) {
        // Litify Intake and Matter records reference their Account via litify_pm__Client__c
        String q = 'SELECT litify_pm__Client__c FROM ' + objectType + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> recs = Database.query(q);
        if (recs.isEmpty())                    throw new AuraHandledException('Record not found: ' + recordId);
        Id accountId = (Id) recs[0].get('litify_pm__Client__c');
        if (accountId == null)                 throw new AuraHandledException('No client/account linked to this record.');
        return accountId;
    }

    private static String resolveFilterField(String objectType) {
        Map<String, String> mapping = new Map<String, String>{
            'Account'                => 'Party__c',
            'litify_pm__Intake__c'   => 'Intake__c',
            'litify_pm__Matter__c'   => 'Matter__c'
        };
        return mapping.get(objectType);
    }

    // ── Wrapper class ─────────────────────────────────────────────────────────

    public class SmsMessageWrapper {
        @AuraEnabled public String  id;
        @AuraEnabled public String  messageBody;
        @AuraEnabled public String  direction;       // lowercase: 'inbound' | 'outbound'
        @AuraEnabled public String  status;          // Dialpad status: sent, delivered, failed, etc.
        @AuraEnabled public String  fromNumber;
        @AuraEnabled public String  toNumber;
        @AuraEnabled public String  contactName;
        @AuraEnabled public String  contactPhone;
        @AuraEnabled public String  createdDate;
        @AuraEnabled public Boolean isCrossRecord;
        @AuraEnabled public String  relatedRecordName;
        @AuraEnabled public String  relatedRecordId;
    }
}
