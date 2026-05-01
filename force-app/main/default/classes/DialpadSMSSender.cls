public class DialpadSMSSender {
    
    // Invocable method wrapper class for input parameters
    public class SendSMSRequest {
        @InvocableVariable(required=true label='Message Text' description='The SMS message content to send')
        public String messageText;
        
        @InvocableVariable(required=true label='To Phone Numbers' description='List of phone numbers to send SMS to (E164 format, max 10 numbers)')
        public List<String> toNumbers;
        
        @InvocableVariable(required=true label='From Number' description='The phone number to send from (must be assigned to user or user group)')
        public String fromNumber;
        
        @InvocableVariable(label='User ID' description='The ID of the user who should send the message')
        public String userId;
        
        @InvocableVariable(label='Sender Group ID' description='The ID of an office, department, or call center that the User should send the message on behalf of')
        public String senderGroupId;
        
        @InvocableVariable(label='Sender Group Type' description='The sender group type (callcenter, department, or office)')
        public String senderGroupType;
        
        @InvocableVariable(label='Channel Hashtag' description='The hashtag of the channel which should receive the SMS')
        public String channelHashtag;
        
        @InvocableVariable(label='Infer Country Code' description='If true, to_numbers will be assumed to be from the specified user country')
        public Boolean inferCountryCode;
        
        @InvocableVariable(label='Media Base64' description='Base64-encoded media attachment (max 500 KB)')
        public String mediaBase64;
    }
    
    // Invocable method wrapper class for output/results
    public class SendSMSResponse {
        @InvocableVariable(label='Success' description='Whether the SMS was sent successfully')
        public Boolean success;
        
        @InvocableVariable(label='Message' description='Success or error message')
        public String message;
        
        @InvocableVariable(label='SMS ID' description='The Dialpad SMS message ID if successful')
        public String smsId;
        
        @InvocableVariable(label='Contact ID' description='The Dialpad contact ID from the response')
        public String contactId;
        
        @InvocableVariable(label='HTTP Status Code' description='The HTTP response status code')
        public Integer statusCode;
    }
    
    // API Request body structure
    public class DialpadSMSAPIRequest {
        public String channelHashtag;
        public String fromNumber;
        public Boolean inferCountryCode;
        public String media;
        public Long senderGroupId;
        public String senderGroupType;
        public String text;
        public List<String> toNumbers;
        public Long userId;
        
        // Convert to Map for JSON serialization with snake_case keys for API
        public Map<String, Object> toApiMap() {
            Map<String, Object> apiMap = new Map<String, Object>();
            
            if (channelHashtag != null) apiMap.put('channel_hashtag', channelHashtag);
            if (fromNumber != null) apiMap.put('from_number', fromNumber);
            if (inferCountryCode != null) apiMap.put('infer_country_code', inferCountryCode);
            if (media != null) apiMap.put('media', media);
            if (senderGroupId != null) apiMap.put('sender_group_id', senderGroupId);
            if (senderGroupType != null) apiMap.put('sender_group_type', senderGroupType);
            if (text != null) apiMap.put('text', text);
            if (toNumbers != null) apiMap.put('to_numbers', toNumbers);
            if (userId != null) apiMap.put('user_id', userId);
            
            return apiMap;
        }
    }
    
    // API Response structure
    public class DialpadSMSAPIResponse {
        public String contact_id;
        public String created_date;
        public String device_type;
        public String direction;
        public String from_number;
        public String id;
        public String message_status;
        public String target_id;
        public String target_type;
        public String text;
        public List<String> to_numbers;
        public String user_id;
    }
    
    /**
     * Invocable method to send SMS via Dialpad API
     * Can be called from Flow, Process Builder, or other automation
     */
    @InvocableMethod(label='Send Dialpad SMS' description='Sends an SMS message through the Dialpad API' category='Communication')
    public static List<SendSMSResponse> sendSMS(List<SendSMSRequest> requests) {
        List<SendSMSResponse> responses = new List<SendSMSResponse>();
        
        for (SendSMSRequest request : requests) {
            responses.add(sendSingleSMS(request));
        }
        
        return responses;
    }
    
    /**
     * Sends a single SMS message
     */
    private static SendSMSResponse sendSingleSMS(SendSMSRequest request) {
        SendSMSResponse response = new SendSMSResponse();
        response.success = false;
        
        try {
            // Validate required fields
            if (String.isBlank(request.messageText)) {
                throw new DialpadSMSException('Message text is required');
            }
            
            if (request.toNumbers == null || request.toNumbers.isEmpty()) {
                throw new DialpadSMSException('At least one recipient phone number is required');
            }
            
            if (request.toNumbers.size() > 10) {
                throw new DialpadSMSException('Maximum of 10 recipient phone numbers allowed');
            }
            
            if (String.isBlank(request.fromNumber)) {
                throw new DialpadSMSException('From number is required');
            }
            
            // Build the API request body
            DialpadSMSAPIRequest apiRequest = new DialpadSMSAPIRequest();
            apiRequest.text = request.messageText;
            apiRequest.toNumbers = request.toNumbers;
            apiRequest.fromNumber = request.fromNumber;
            apiRequest.channelHashtag = request.channelHashtag;
            apiRequest.inferCountryCode = request.inferCountryCode != null ? request.inferCountryCode : false;
            apiRequest.media = request.mediaBase64;
            
            // Parse optional numeric fields
            if (!String.isBlank(request.userId)) {
                try {
                    apiRequest.userId = Long.valueOf(request.userId);
                } catch (Exception e) {
                    throw new DialpadSMSException('Invalid User ID format: ' + request.userId);
                }
            }
            
            if (!String.isBlank(request.senderGroupId)) {
                try {
                    apiRequest.senderGroupId = Long.valueOf(request.senderGroupId);
                } catch (Exception e) {
                    throw new DialpadSMSException('Invalid Sender Group ID format: ' + request.senderGroupId);
                }
            }
            
            // Validate sender group type if provided
            if (!String.isBlank(request.senderGroupType)) {
                String senderType = request.senderGroupType.toLowerCase();
                if (senderType != 'callcenter' && senderType != 'department' && senderType != 'office') {
                    throw new DialpadSMSException('Invalid sender group type. Must be: callcenter, department, or office');
                }
                apiRequest.senderGroupType = senderType;
            }
            
            // Make the HTTP callout
            HttpResponse httpResponse = makeDialpadAPICall(apiRequest);
            response.statusCode = httpResponse.getStatusCode();
            
            // Process response
            if (httpResponse.getStatusCode() == 200) {
                DialpadSMSAPIResponse apiResponse = (DialpadSMSAPIResponse) JSON.deserialize(
                    httpResponse.getBody(), 
                    DialpadSMSAPIResponse.class
                );
                
                response.success = true;
                response.message = 'SMS sent successfully';
                response.smsId = apiResponse.id;
                response.contactId = apiResponse.contact_id;
                
                // Log success
                nebula.Logger.info('Dialpad SMS sent successfully');
               /*    .setField('SMS ID', apiResponse.id)
                    .setField('From Number', request.fromNumber)
                    .setField('To Numbers', String.join(request.toNumbers, ', '));*/
                nebula.Logger.saveLog();
                
            } else {
                // Handle error responses
                String errorBody = httpResponse.getBody();
                response.success = false;
                response.message = 'API Error (Status ' + httpResponse.getStatusCode() + '): ' + errorBody;
                
                // Log error
                nebula.Logger.error('Dialpad SMS API error');
                    /*.setField('Status Code', String.valueOf(httpResponse.getStatusCode()))
                    .setField('Response Body', errorBody)
                    .setField('From Number', request.fromNumber)
                    .setField('To Numbers', String.join(request.toNumbers, ', '));*/
                nebula.Logger.saveLog();
            }
            
        } catch (DialpadSMSException e) {
            response.success = false;
            response.message = 'Validation Error: ' + e.getMessage();

            nebula.Logger.error('ialpad SMS validation error. Message: ' + e.getMessage());
            
            /*nebula.Logger.error('Dialpad SMS validation error')
                .setField('Error Message', e.getMessage())
                .setField('From Number', request.fromNumber);
            */
            nebula.Logger.saveLog();
            
        } catch (Exception e) {
            response.success = false;
            response.message = 'Unexpected Error: ' + e.getMessage();
            
            nebula.Logger.error(response.message);

            /*nebula.Logger.error('Dialpad SMS unexpected error')
                .setField('Error Message', e.getMessage())
                .setField('Stack Trace', e.getStackTraceString())
                .setField('From Number', request.fromNumber);*/
            nebula.Logger.saveLog();
        }
        
        return response;
    }
    
    /**
     * Makes the HTTP callout to Dialpad API
     */
    private static HttpResponse makeDialpadAPICall(DialpadSMSAPIRequest requestBody) {
        // Use Named Credential for authentication
        // The Named Credential should be set up with the Dialpad API endpoint and Bearer token
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Dialpad_API/api/v2/sms');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        
        // Serialize request body with snake_case keys for API
        String jsonBody = JSON.serialize(requestBody.toApiMap(), true);
        req.setBody(jsonBody);
        
        // Set timeout (max 120 seconds for callouts)
        req.setTimeout(120000);
        
        // Make the callout
        Http http = new Http();
        HttpResponse response = http.send(req);
        
        return response;
    }
    
    /**
     * Custom exception class for Dialpad SMS errors
     */
    public class DialpadSMSException extends Exception {}
}