import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSmsHistory from '@salesforce/apex/SmsMessagingController.getSmsHistory';
import sendSms from '@salesforce/apex/SmsMessagingController.sendSms';

const MAX_CHARS = 1600;

// Objects that display the "show all account messages" toggle
const TOGGLE_OBJECTS = new Set(['Intake__c', 'Matter__c']);

const STATUS_ICONS = {
    Delivered: 'utility:check',
    Sent:      'utility:routing_offline',
    Failed:    'utility:error',
    Pending:   'utility:clock'
};
const STATUS_CLASSES = {
    Delivered: 'sms-status-delivered',
    Sent:      'sms-status-sent',
    Failed:    'sms-status-failed',
    Pending:   'sms-status-pending'
};

export default class SmsMessaging extends LightningElement {
    @api recordId;
    @api objectApiName;  // automatically set by platform on record pages
    @api contactName;

    @track showAllMessages  = false;
    @track isLoading        = false;
    @track isSending        = false;
    @track messages         = [];
    @track newMessageBody   = '';
    @track hasError         = false;
    @track errorMessage     = '';
    @track sendError        = '';

    // ── lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadMessages();
    }

    // ── computed ─────────────────────────────────────────────────────────────

    get contactDisplayName() {
        return this.contactName || 'Contact';
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

    _toViewModel(w) {
        const isOutbound = w.direction === 'Outbound';
        const status     = w.status || 'Sent';
        const cross      = w.isCrossRecord === true;

        let bubbleClass = 'sms-message ';
        if (isOutbound) {
            bubbleClass += cross ? 'sms-message--cross-outbound' : 'sms-message--outbound';
        } else {
            bubbleClass += cross ? 'sms-message--cross-inbound' : 'sms-message--inbound';
        }

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
            statusIcon:        STATUS_ICONS[status]   || STATUS_ICONS.Sent,
            statusClass:       STATUS_CLASSES[status] || STATUS_CLASSES.Sent,
            fromDisplay:       w.fromNumber || 'Contact',
            isRead:            w.isRead || false
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

        this.isSending = true;
        this.sendError = '';

        const promise = this.recordId
            ? sendSms({ recordId: this.recordId, messageBody: body })
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
                    title: 'Message Sent', message: 'SMS queued successfully.', variant: 'success'
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
            status:            'Sent',
            statusIcon:        STATUS_ICONS.Sent,
            statusClass:       STATUS_CLASSES.Sent,
            fromDisplay:       'You',
            isRead:            true
        };
    }

    // ── mock data (no recordId — App Builder preview) ─────────────────────────

    _mockMessages() {
        const ago = (mins) => new Date(Date.now() - mins * 60 * 1000).toISOString();

        // Simulate a mix: some belong to this intake, some to another
        const showCross = this.showAllMessages;
        const msgs = [
            { id:'1', direction:'Inbound',  messageBody:'Hi, is this appointment still on for tomorrow?', createdDate:ago(62), status:'Delivered', fromNumber:'+15551234567', isRead:true,  isCrossRecord:false, relatedRecordName:null },
            { id:'2', direction:'Outbound', messageBody:"Yes, confirmed for 2 PM. We'll send a reminder.", createdDate:ago(58), status:'Delivered', fromNumber:'',             isRead:true,  isCrossRecord:false, relatedRecordName:null },
            { id:'3', direction:'Inbound',  messageBody:'Great! Do I need to bring anything?',             createdDate:ago(55), status:'Delivered', fromNumber:'+15551234567', isRead:true,  isCrossRecord:false, relatedRecordName:null },
            { id:'4', direction:'Outbound', messageBody:'Just your ID and insurance card.',                createdDate:ago(50), status:'Delivered', fromNumber:'',             isRead:true,  isCrossRecord:false, relatedRecordName:null },
            { id:'5', direction:'Inbound',  messageBody:'Perfect. See you then!',                         createdDate:ago(3),  status:'Delivered', fromNumber:'+15551234567', isRead:false, isCrossRecord:false, relatedRecordName:null }
        ];

        if (showCross) {
            msgs.splice(2, 0,
                { id:'x1', direction:'Outbound', messageBody:'Your renewal documents are ready for review.', createdDate:ago(57), status:'Delivered', fromNumber:'', isRead:true, isCrossRecord:true, relatedRecordName:'Matter: Acme Renewal 2025' },
                { id:'x2', direction:'Inbound',  messageBody:'Thanks, I will take a look this afternoon.',   createdDate:ago(56), status:'Delivered', fromNumber:'+15551234567', isRead:true, isCrossRecord:true, relatedRecordName:'Matter: Acme Renewal 2025' }
            );
            msgs.push(
                { id:'x3', direction:'Outbound', messageBody:'Following up on your general account inquiry.', createdDate:ago(1), status:'Sent', fromNumber:'', isRead:true, isCrossRecord:true, relatedRecordName:'Acme Corp (Account)' }
            );
        }

        return msgs.map(w => this._toViewModel(w));
    }

    _buildMockOutbound(body) {
        return {
            id: `mock-${Date.now()}`, direction:'Outbound', messageBody: body,
            createdDate: new Date().toISOString(), status:'Sent',
            fromNumber:'', isRead:true, isCrossRecord:false, relatedRecordName:null
        };
    }
}
