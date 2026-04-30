import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSmsHistory from '@salesforce/apex/SmsMessagingController.getSmsHistory';
import sendSms from '@salesforce/apex/SmsMessagingController.sendSms';

const MAX_CHARS = 1600;

// Status icon mapping
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
    @api recordId;       // Contact / Lead / Account record Id from record page
    @api contactName;    // Optional: override display name

    @track isModalOpen  = false;
    @track isLoading    = false;
    @track isSending    = false;
    @track messages     = [];
    @track newMessageBody = '';
    @track hasError     = false;
    @track errorMessage = '';
    @track sendError    = '';

    // ── computed ────────────────────────────────────────────────────────────

    get contactDisplayName() {
        return this.contactName || 'Contact';
    }

    get hasMessages() {
        return this.messages && this.messages.length > 0;
    }

    get unreadCount() {
        const count = this.messages.filter(m => m.isInbound && !m.isRead).length;
        return count > 0 ? count : null;
    }

    get charCountDisplay() {
        const remaining = MAX_CHARS - (this.newMessageBody || '').length;
        return `${remaining}`;
    }

    get isSendDisabled() {
        return this.isSending || !this.newMessageBody || this.newMessageBody.trim().length === 0;
    }

    // ── modal lifecycle ──────────────────────────────────────────────────────

    openModal() {
        this.isModalOpen = true;
        this.loadMessages();
    }

    closeModal() {
        this.isModalOpen  = false;
        this.sendError    = '';
    }

    // ── data loading ─────────────────────────────────────────────────────────

    loadMessages() {
        if (!this.recordId) {
            this.messages = this._mockMessages();
            return;
        }

        this.isLoading    = true;
        this.hasError     = false;
        this.errorMessage = '';

        getSmsHistory({ recordId: this.recordId })
            .then(result => {
                this.messages = this._mapMessages(result);
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

    _mapMessages(records) {
        return records.map(r => this._toViewModel(r));
    }

    _toViewModel(r) {
        const isOutbound = r.Direction__c === 'Outbound';
        const status     = r.Status__c || 'Sent';
        return {
            id:            r.Id,
            body:          r.Message_Body__c,
            isOutbound,
            isInbound:     !isOutbound,
            bubbleClass:   isOutbound ? 'sms-message sms-message--outbound' : 'sms-message sms-message--inbound',
            formattedDate: this._formatDate(r.CreatedDate),
            status,
            statusIcon:    STATUS_ICONS[status]  || STATUS_ICONS.Sent,
            statusClass:   STATUS_CLASSES[status] || STATUS_CLASSES.Sent,
            fromDisplay:   r.From_Number__c || 'Contact',
            isRead:        r.Is_Read__c || false
        };
    }

    _formatDate(isoString) {
        if (!isoString) return '';
        const d = new Date(isoString);
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
        // Defer one tick so DOM is painted before we measure scroll height
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const container = this.refs?.messageContainer;
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 50);
    }

    // ── composing & sending ──────────────────────────────────────────────────

    handleMessageInput(event) {
        this.newMessageBody = event.target.value;
        this.sendError      = '';
    }

    handleKeyDown(event) {
        // Ctrl+Enter or Cmd+Enter submits
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

        const sendPromise = this.recordId
            ? sendSms({ recordId: this.recordId, messageBody: body })
            : Promise.resolve(this._buildMockOutbound(body));

        sendPromise
            .then(newRecord => {
                this.messages    = [...this.messages, this._toViewModelFromSend(newRecord, body)];
                this.newMessageBody = '';
                this._scrollToBottom();
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Message Sent',
                    message: 'Your SMS was queued successfully.',
                    variant: 'success'
                }));
            })
            .catch(error => {
                this.sendError = error?.body?.message || 'Failed to send message. Please try again.';
            })
            .finally(() => {
                this.isSending = false;
            });
    }

    _toViewModelFromSend(record, fallbackBody) {
        if (record?.Id) return this._toViewModel(record);
        return {
            id:            `local-${Date.now()}`,
            body:          fallbackBody,
            isOutbound:    true,
            isInbound:     false,
            bubbleClass:   'sms-message sms-message--outbound',
            formattedDate: this._formatDate(new Date().toISOString()),
            status:        'Sent',
            statusIcon:    STATUS_ICONS.Sent,
            statusClass:   STATUS_CLASSES.Sent,
            fromDisplay:   'You',
            isRead:        true
        };
    }

    // ── mock data (used when no recordId is present, e.g. App Builder preview) ──

    _mockMessages() {
        const now  = new Date();
        const ago  = (mins) => new Date(now - mins * 60 * 1000).toISOString();
        return [
            {
                Id: '1', Direction__c: 'Inbound',  Message_Body__c: 'Hi, is this appointment still on for tomorrow?',
                CreatedDate: ago(62), Status__c: 'Delivered', From_Number__c: '+15551234567', Is_Read__c: true
            },
            {
                Id: '2', Direction__c: 'Outbound', Message_Body__c: 'Yes, confirmed for 2 PM. We\'ll send a reminder.',
                CreatedDate: ago(58), Status__c: 'Delivered', From_Number__c: '', Is_Read__c: true
            },
            {
                Id: '3', Direction__c: 'Inbound',  Message_Body__c: 'Great, thanks! Do I need to bring anything?',
                CreatedDate: ago(55), Status__c: 'Delivered', From_Number__c: '+15551234567', Is_Read__c: true
            },
            {
                Id: '4', Direction__c: 'Outbound', Message_Body__c: 'Just your ID and insurance card.',
                CreatedDate: ago(50), Status__c: 'Delivered', From_Number__c: '', Is_Read__c: true
            },
            {
                Id: '5', Direction__c: 'Inbound',  Message_Body__c: 'Perfect. See you then!',
                CreatedDate: ago(3), Status__c: 'Delivered', From_Number__c: '+15551234567', Is_Read__c: false
            }
        ].map(r => this._toViewModel(r));
    }

    _buildMockOutbound(body) {
        return {
            Id: `mock-${Date.now()}`,
            Direction__c:    'Outbound',
            Message_Body__c: body,
            CreatedDate:     new Date().toISOString(),
            Status__c:       'Sent',
            From_Number__c:  '',
            Is_Read__c:      true
        };
    }
}
