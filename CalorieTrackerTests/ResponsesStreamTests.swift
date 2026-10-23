import Testing
@testable import CalorieTracker

struct ResponsesStreamTests {
    @Test func textDelta() {
        #expect(ResponsesStreamEvent.parse(line: #"data: {"type":"response.output_text.delta","delta":"Hel"}"#) == .textDelta("Hel"))
    }

    @Test func completed() {
        #expect(ResponsesStreamEvent.parse(line: #"data: {"type":"response.completed","response":{}}"#) == .completed)
    }

    @Test func failedWithUsageLimit() {
        let line = #"data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"cap"}}}"#
        #expect(ResponsesStreamEvent.parse(line: line) == .failed(code: "subscription_sharing_usage_limit_exceeded", message: "cap"))
    }

    @Test func incomplete() {
        let line = #"data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#
        #expect(ResponsesStreamEvent.parse(line: line) == .incomplete(reason: "max_output_tokens"))
    }

    @Test func ignoresNonDataLines() {
        #expect(ResponsesStreamEvent.parse(line: "event: response.output_text.delta") == nil)
        #expect(ResponsesStreamEvent.parse(line: "data: [DONE]") == nil)
        #expect(ResponsesStreamEvent.parse(line: "data: not json") == nil)
    }

    @Test func unknownTypesPassThrough() {
        #expect(ResponsesStreamEvent.parse(line: #"data: {"type":"response.created"}"#) == .other(type: "response.created"))
    }
}
