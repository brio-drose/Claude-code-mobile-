@IsTest
private class DialpadSMSSenderTest {
    
    /**
     * Mock HTTP response for successful SMS send
     */
    private class DialpadSMSSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            // Verify request setup
            System.assertEquals('POST', req.getMethod());
            System.assertEquals('application/json', req.getHeader('Content-Type'));
            System.assertEquals('application/json', req.getHeader('Accept'));
            System.assert(req.getEndpoint().contains('/api/v2/sms'));
            
            // Create successful response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"contact_id": "1000", "created_date": "2013-01-01T00:00:00", ' +
                       '"device_type": "public_api", "direction": "outbound", ' +
                       '"from_number": "+12155551212", "id": "1004", ' +
                       '"message_status": "pending", "target_id": "2", ' +
                       '"target_type": "user", "text": "Test text", ' +
                       '"to_numbers": ["+12673371300"], "user_id": "1234565"}');
            return res;
        }
    }
    
    /**
     * Mock HTTP response for API error
     */
    private class DialpadSMSErrorMock implements HttpCalloutMock {
        private Integer statusCode;
        private String errorMessage;
        
        public DialpadSMSErrorMock(Integer statusCode, String errorMessage) {
            this.statusCode = statusCode;
            this.errorMessage = errorMessage;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody('{"error": "' + errorMessage + '"}');
            return res;
        }
    }
    
    /**
     * Test successful SMS send with minimal required fields
     */
    @IsTest
    static void testSendSMS_Success_MinimalFields() {
        // Set mock callout
        Test.setMock(HttpCalloutMock.class, new DialpadSMSSuccessMock());
        
        // Create request
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Test message';
        request.toNumbers = new List<String>{'+12673371300'};
        request.fromNumber = '+12155551212';
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(true, response.success, 'SMS should be sent successfully');
        System.assertEquals('SMS sent successfully', response.message, 'Success message should be returned');
        System.assertEquals('1004', response.smsId, 'SMS ID should be returned');
        System.assertEquals('1000', response.contactId, 'Contact ID should be returned');
        System.assertEquals(200, response.statusCode, 'Status code should be 200');
    }
    
    /**
     * Test successful SMS send with all optional fields
     */
    @IsTest
    static void testSendSMS_Success_AllFields() {
        // Set mock callout
        Test.setMock(HttpCalloutMock.class, new DialpadSMSSuccessMock());
        
        // Create request with all fields
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Complete test message';
        request.toNumbers = new List<String>{'+12673371300', '+12673371301'};
        request.fromNumber = '+12155551212';
        request.userId = '1234565';
        request.senderGroupId = '6789';
        request.senderGroupType = 'callcenter';
        request.channelHashtag = '#support';
        request.inferCountryCode = true;
        request.mediaBase64 = 'SGVsbG8gV29ybGQ='; // "Hello World" in base64
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(true, response.success, 'SMS should be sent successfully');
        System.assertEquals(200, response.statusCode, 'Status code should be 200');
    }
    
    /**
     * Test validation error - missing message text
     */
    @IsTest
    static void testSendSMS_ValidationError_MissingMessageText() {
        // Create request without message text
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.toNumbers = new List<String>{'+12673371300'};
        request.fromNumber = '+12155551212';
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify error response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(false, response.success, 'Should fail validation');
        System.assert(response.message.contains('Message text is required'), 'Should return validation error message');
    }
    
    /**
     * Test validation error - missing to numbers
     */
    @IsTest
    static void testSendSMS_ValidationError_MissingToNumbers() {
        // Create request without to numbers
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Test message';
        request.fromNumber = '+12155551212';
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify error response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(false, response.success, 'Should fail validation');
        System.assert(response.message.contains('At least one recipient phone number is required'), 
                     'Should return validation error message');
    }
    
    /**
     * Test validation error - too many recipients
     */
    @IsTest
    static void testSendSMS_ValidationError_TooManyRecipients() {
        // Create request with more than 10 recipients
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Test message';
        request.toNumbers = new List<String>{
            '+12673371301', '+12673371302', '+12673371303', '+12673371304', '+12673371305',
            '+12673371306', '+12673371307', '+12673371308', '+12673371309', '+12673371310',
            '+12673371311'
        };
        request.fromNumber = '+12155551212';
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify error response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(false, response.success, 'Should fail validation');
        System.assert(response.message.contains('Maximum of 10 recipient phone numbers allowed'), 
                     'Should return validation error message');
    }
    
    /**
     * Test validation error - missing from number
     */
    @IsTest
    static void testSendSMS_ValidationError_MissingFromNumber() {
        // Create request without from number
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Test message';
        request.toNumbers = new List<String>{'+12673371300'};
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify error response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(false, response.success, 'Should fail validation');
        System.assert(response.message.contains('From number is required'), 
                     'Should return validation error message');
    }
    
    /**
     * Test validation error - invalid user ID format
     */
    @IsTest
    static void testSendSMS_ValidationError_InvalidUserId() {
        // Create request with invalid user ID
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Test message';
        request.toNumbers = new List<String>{'+12673371300'};
        request.fromNumber = '+12155551212';
        request.userId = 'invalid_user_id';
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify error response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(false, response.success, 'Should fail validation');
        System.assert(response.message.contains('Invalid User ID format'), 
                     'Should return validation error message');
    }
    
    /**
     * Test validation error - invalid sender group ID format
     */
    @IsTest
    static void testSendSMS_ValidationError_InvalidSenderGroupId() {
        // Create request with invalid sender group ID
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Test message';
        request.toNumbers = new List<String>{'+12673371300'};
        request.fromNumber = '+12155551212';
        request.senderGroupId = 'not_a_number';
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify error response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(false, response.success, 'Should fail validation');
        System.assert(response.message.contains('Invalid Sender Group ID format'), 
                     'Should return validation error message');
    }
    
    /**
     * Test validation error - invalid sender group type
     */
    @IsTest
    static void testSendSMS_ValidationError_InvalidSenderGroupType() {
        // Create request with invalid sender group type
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Test message';
        request.toNumbers = new List<String>{'+12673371300'};
        request.fromNumber = '+12155551212';
        request.senderGroupType = 'invalid_type';
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify error response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(false, response.success, 'Should fail validation');
        System.assert(response.message.contains('Invalid sender group type'), 
                     'Should return validation error message');
    }
    
    /**
     * Test valid sender group types
     */
    @IsTest
    static void testSendSMS_ValidSenderGroupTypes() {
        // Set mock callout
        Test.setMock(HttpCalloutMock.class, new DialpadSMSSuccessMock());
        
        List<String> validTypes = new List<String>{'callcenter', 'department', 'office'};
        
        Test.startTest();
        for (String senderType : validTypes) {
            DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
            request.messageText = 'Test message';
            request.toNumbers = new List<String>{'+12673371300'};
            request.fromNumber = '+12155551212';
            request.senderGroupType = senderType;
            
            List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
                new List<DialpadSMSSender.SendSMSRequest>{request}
            );
            
            System.assertEquals(true, responses[0].success, 
                               'Should accept ' + senderType + ' as valid sender group type');
        }
        Test.stopTest();
    }
    
    /**
     * Test API error response - 400 Bad Request
     */
    @IsTest
    static void testSendSMS_APIError_BadRequest() {
        // Set mock callout for error
        Test.setMock(HttpCalloutMock.class, new DialpadSMSErrorMock(400, 'Bad request'));
        
        // Create request
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Test message';
        request.toNumbers = new List<String>{'+12673371300'};
        request.fromNumber = '+12155551212';
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify error response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(false, response.success, 'Should fail due to API error');
        System.assert(response.message.contains('API Error'), 'Should return API error message');
        System.assertEquals(400, response.statusCode, 'Status code should be 400');
    }
    
    /**
     * Test API error response - 401 Unauthorized
     */
    @IsTest
    static void testSendSMS_APIError_Unauthorized() {
        // Set mock callout for error
        Test.setMock(HttpCalloutMock.class, new DialpadSMSErrorMock(401, 'Unauthorized'));
        
        // Create request
        DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
        request.messageText = 'Test message';
        request.toNumbers = new List<String>{'+12673371300'};
        request.fromNumber = '+12155551212';
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(
            new List<DialpadSMSSender.SendSMSRequest>{request}
        );
        Test.stopTest();
        
        // Verify error response
        System.assertEquals(1, responses.size(), 'Should return one response');
        DialpadSMSSender.SendSMSResponse response = responses[0];
        System.assertEquals(false, response.success, 'Should fail due to auth error');
        System.assertEquals(401, response.statusCode, 'Status code should be 401');
    }
    
    /**
     * Test bulk processing - multiple SMS requests
     */
    @IsTest
    static void testSendSMS_BulkProcessing() {
        // Set mock callout
        Test.setMock(HttpCalloutMock.class, new DialpadSMSSuccessMock());
        
        // Create multiple requests
        List<DialpadSMSSender.SendSMSRequest> requests = new List<DialpadSMSSender.SendSMSRequest>();
        
        for (Integer i = 0; i < 3; i++) {
            DialpadSMSSender.SendSMSRequest request = new DialpadSMSSender.SendSMSRequest();
            request.messageText = 'Test message ' + i;
            request.toNumbers = new List<String>{'+1267337130' + i};
            request.fromNumber = '+12155551212';
            requests.add(request);
        }
        
        Test.startTest();
        List<DialpadSMSSender.SendSMSResponse> responses = DialpadSMSSender.sendSMS(requests);
        Test.stopTest();
        
        // Verify responses
        System.assertEquals(3, responses.size(), 'Should return three responses');
        for (DialpadSMSSender.SendSMSResponse response : responses) {
            System.assertEquals(true, response.success, 'All SMS should be sent successfully');
        }
    }
}