import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSmsHistory from '@salesforce/apex/SmsMessagingController.getSmsHistory';
import sendSms from '@salesforce/apex/SmsMessagingController.sendSms';

const MAX_CHARS = 1600;

const TOGGLE_OBJECTS = new Set(['litify_pm__Intake__c', 'litify_pm__Matter__c']);

// Dialpad message_status → icon mapping (all lowercase keys)
const STATUS_ICONS = {
    delivered:   'utility:check',
    sent:        'utility:routing_offline',
    queued:      'utility:clock',
    failed:      'utility:error',
    undelivered: 'utility:error',
    received:    'utility:check'
};
const STATUS_CLASSES = {
    delivered:   'sms-status-delivered',
    sent:        'sms-status-sent',
    queued:      'sms-status-pending',
    failed:      'sms-status-failed',
    undelivered: 'sms-status-failed',
    received:    'sms-status-delivered'
};

export default class SmsMessaging extends LightningElement {
    @api recordId;
    @api objectApiName;   // automatically populated by platform on record pages
    @api contactName;     // optional override for the header display name
    @api fromNumber;      // Dialpad "from" number — configure in App Builder

    @track showAllMessages  = false;
    @track isLoading        = false;
    @track isSending        = false;
    @track messages         = [];
    @track newMessageBody   = '';
    @track hasError         = false;
    @track errorMessage     = '';
    @track sendError        = '';

    // Derived from loaded messages — used for the send call and header
    _contactPhone = null;
    _contactName  = null;

    // ── lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadMessages();
    }

    // ── computed ─────────────────────────────────────────────────────────────

    get contactDisplayName() {
        return this.contactName || this._contactName || 'Contact';
    }

    get showToggle() {
        return this.objectApiName && TOGGLE_OBJECTS.has(this.objectApiName);
    }

    get hasMessages() {
        return this.messages && this.messages.length > 0;
    }

    get charCountDisplay() {
        return MAX_CHARS - (this.newMessageBody || '').length;
    }

    get isSendDisabled() {
        return this.isSending || !(this.newMessageBody || '').trim();
    }

    // ── toggle ────────────────────────────────────────────────────────────────

    handleToggle(event) {
        this.showAllMessages = event.target.checked;
        this.loadMessages();
    }

    // ── data loading ─────────────────────────────────────────────────────────

    loadMessages() {
        if (!this.recordId) {
            this.messages = this._mockMessages();
            this._scrollToBottom();
            return;
        }

        this.isLoading    = true;
        this.hasError     = false;
        this.errorMessage = '';

        getSmsHistory({ recordId: this.recordId, showAll: this.showAllMessages })
            .then(result => {
                this.messages = result.map(w => this._toViewModel(w));
                this._deriveContactInfo(result);
                this._scrollToBottom();
            })
            .catch(error => {
                this.hasError     = true;
                this.errorMessage = error?.body?.message || 'Failed to load SMS history.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Pull contact name and phone from the most recent inbound message
    _deriveContactInfo(wrappers) {
        for (let i = wrappers.length - 1; i >= 0; i--) {
            const w = wrappers[i];
            if (w.direction?.toLowerCase() === 'inbound') {
                if (w.contactName)  this._contactName  = w.contactName;
                if (w.contactPhone) this._contactPhone = w.contactPhone;
                if (w.fromNumber && !this._contactPhone) this._contactPhone = w.fromNumber;
                break;
            }
        }
    }

    _toViewModel(w) {
        const isOutbound = (w.direction || '').toLowerCase() === 'outbound';
        const status     = (w.status || 'sent').toLowerCase();
        const cross      = w.isCrossRecord === true;

        let bubbleClass = 'sms-message ';
        if (isOutbound) {
            bubbleClass += cross ? 'sms-message--cross-outbound' : 'sms-message--outbound';
        } else {
            bubbleClass += cross ? 'sms-message--cross-inbound' : 'sms-message--inbound';
        }

        // For inbound messages the contact's number is from_number;
        // for outbound it's to_number — use whichever is the external party
        const contactPhone = isOutbound ? w.toNumber : w.fromNumber;

        return {
            id:                w.id,
            body:              w.messageBody,
            isOutbound,
            isInbound:         !isOutbound,
            isCrossRecord:     cross,
            relatedRecordName: w.relatedRecordName,
            bubbleClass,
            formattedDate:     this._formatDate(w.createdDate),
            status,
            statusIcon:        STATUS_ICONS[status]   || STATUS_ICONS.sent,
            statusClass:       STATUS_CLASSES[status] || STATUS_CLASSES.sent,
            fromDisplay:       w.contactName || contactPhone || 'Contact',
            isRead:            !cross   // cross-record msgs treated as contextual, not unread
        };
    }

    _formatDate(isoString) {
        if (!isoString) return '';
        const d     = new Date(isoString);
        const today = new Date();
        const isToday =
            d.getDate()     === today.getDate()    &&
            d.getMonth()    === today.getMonth()   &&
            d.getFullYear() === today.getFullYear();
        if (isToday) {
            return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        }
        return d.toLocaleDateString([], { month: 'short', day: 'numeric' }) +
               ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    _scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const el = this.refs?.messageContainer;
            if (el) el.scrollTop = el.scrollHeight;
        }, 50);
    }

    // ── composing & sending ───────────────────────────────────────────────────

    handleMessageInput(event) {
        this.newMessageBody = event.target.value;
        this.sendError      = '';
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
            event.preventDefault();
            this.sendMessage();
        }
    }

    sendMessage() {
        const body = (this.newMessageBody || '').trim();
        if (!body) return;

        if (this.recordId && !this._contactPhone) {
            this.sendError = 'No recipient phone number found. Load messages first or check the record.';
            return;
        }
        if (this.recordId && !this.fromNumber) {
            this.sendError = 'No "From Number" configured. Set it in the component properties.';
            return;
        }

        this.isSending = true;
        this.sendError = '';

        const promise = this.recordId
            ? sendSms({
                recordId:    this.recordId,
                messageBody: body,
                toNumber:    this._contactPhone,
                fromNumber:  this.fromNumber
              })
            : Promise.resolve(this._buildMockOutbound(body));

        promise
            .then(wrapper => {
                const vm = wrapper?.id
                    ? this._toViewModel(wrapper)
                    : this._toViewModelFromBody(body);
                this.messages       = [...this.messages, vm];
                this.newMessageBody = '';
                this._scrollToBottom();
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Message Sent', message: 'SMS sent via Dialpad.', variant: 'success'
                }));
            })
            .catch(error => {
                this.sendError = error?.body?.message || 'Failed to send. Please try again.';
            })
            .finally(() => {
                this.isSending = false;
            });
    }

    _toViewModelFromBody(body) {
        return {
            id:                `local-${Date.now()}`,
            body,
            isOutbound:        true,
            isInbound:         false,
            isCrossRecord:     false,
            relatedRecordName: null,
            bubbleClass:       'sms-message sms-message--outbound',
            formattedDate:     this._formatDate(new Date().toISOString()),
            status:            'sent',
            statusIcon:        STATUS_ICONS.sent,
            statusClass:       STATUS_CLASSES.sent,
            fromDisplay:       'You',
            isRead:            true
        };
    }

    // ── mock data (App Builder preview — no recordId) ─────────────────────────

    _mockMessages() {
        const ago = (mins) => new Date(Date.now() - mins * 60 * 1000).toISOString();
        const showCross = this.showAllMessages;

        const msgs = [
            { id:'1', direction:'inbound',  messageBody:'Hi, is the appointment still on for tomorrow?', createdDate:ago(62), status:'delivered', fromNumber:'+15551234567', toNumber:'+18005559876', contactName:'Sarah Mitchell', contactPhone:'+15551234567', isCrossRecord:false, relatedRecordName:null },
            { id:'2', direction:'outbound', messageBody:"Yes, confirmed for 2 PM. We'll send a reminder.", createdDate:ago(58), status:'delivered', fromNumber:'+18005559876', toNumber:'+15551234567', contactName:'Sarah Mitchell', contactPhone:'+15551234567', isCrossRecord:false, relatedRecordName:null },
            { id:'3', direction:'inbound',  messageBody:'Great! Do I need to bring anything?',            createdDate:ago(55), status:'received',  fromNumber:'+15551234567', toNumber:'+18005559876', contactName:'Sarah Mitchell', contactPhone:'+15551234567', isCrossRecord:false, relatedRecordName:null },
            { id:'4', direction:'outbound', messageBody:'Just your ID and insurance card.',               createdDate:ago(50), status:'delivered', fromNumber:'+18005559876', toNumber:'+15551234567', contactName:'Sarah Mitchell', contactPhone:'+15551234567', isCrossRecord:false, relatedRecordName:null },
            { id:'5', direction:'inbound',  messageBody:'Perfect. See you then!',                        createdDate:ago(3),  status:'received',  fromNumber:'+15551234567', toNumber:'+18005559876', contactName:'Sarah Mitchell', contactPhone:'+15551234567', isCrossRecord:false, relatedRecordName:null }
        ];

        if (showCross) {
            msgs.splice(2, 0,
                { id:'x1', direction:'outbound', messageBody:'Your renewal documents are ready for review.', createdDate:ago(57), status:'delivered', fromNumber:'+18005559876', toNumber:'+15551234567', contactName:'Sarah Mitchell', contactPhone:'+15551234567', isCrossRecord:true, relatedRecordName:'Matter: Acme Renewal 2025' },
                { id:'x2', direction:'inbound',  messageBody:'Thanks, I will look at them this afternoon.',  createdDate:ago(56), status:'received',  fromNumber:'+15551234567', toNumber:'+18005559876', contactName:'Sarah Mitchell', contactPhone:'+15551234567', isCrossRecord:true, relatedRecordName:'Matter: Acme Renewal 2025' }
            );
            msgs.push(
                { id:'x3', direction:'outbound', messageBody:'Following up on your general account inquiry.', createdDate:ago(1), status:'sent', fromNumber:'+18005559876', toNumber:'+15551234567', contactName:'Sarah Mitchell', contactPhone:'+15551234567', isCrossRecord:true, relatedRecordName:'Acme Corp (Account)' }
            );
        }

        // Seed contact info for the mock send flow
        this._contactPhone = '+15551234567';
        this._contactName  = 'Sarah Mitchell';

        return msgs.map(w => this._toViewModel(w));
    }

    _buildMockOutbound(body) {
        return {
            id: `mock-${Date.now()}`, direction:'outbound', messageBody: body,
            createdDate: new Date().toISOString(), status:'sent',
            fromNumber: this.fromNumber || '+18005559876',
            toNumber:   this._contactPhone || '+15551234567',
            contactName: this._contactName, contactPhone: this._contactPhone,
            isCrossRecord: false, relatedRecordName: null
        };
    }
}
