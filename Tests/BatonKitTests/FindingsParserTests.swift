@testable import BatonKit
import Testing

struct FindingsParserTests {
    @Test("plain JSON array")
    func plainArray() throws {
        let json = #"[{"file":"a.swift","line":3,"severity":"high","title":"t","body":"b"}]"#
        let parsed = try FindingsParser.parse(json)
        #expect(parsed.findings.count == 1)
        #expect(parsed.findings[0].severity == .high)
        #expect(parsed.findings[0].line == 3)
    }

    @Test("findings payload object")
    func payload() throws {
        let json = #"{"findings":[{"file":"a","severity":"low","title":"t","body":"b"}]}"#
        let parsed = try FindingsParser.parse(json)
        #expect(parsed.findings.count == 1)
    }

    @Test("fenced json block")
    func fenced() throws {
        let text = """
        Here are the findings:
        ```json
        [{"file":"a","severity":"medium","title":"t","body":"b"}]
        ```
        Done.
        """
        let parsed = try FindingsParser.parse(text)
        #expect(parsed.findings.count == 1)
        #expect(parsed.findings[0].severity == .medium)
    }

    @Test("brace-balanced extraction from surrounding prose, ignoring string braces")
    func braceBalanced() throws {
        let text = #"I think {"findings":[{"file":"a","severity":"low","title":"has } brace","body":"b"}]} overall."#
        let parsed = try FindingsParser.parse(text)
        #expect(parsed.findings.count == 1)
        #expect(parsed.findings[0].title == "has } brace")
    }

    @Test("a mistyped `line` is coerced and does not drop the rest of the batch")
    func lenientLineType() throws {
        // First finding emits line as a string; a strict array decode would abort
        // the whole batch. Both findings must survive, with line coerced to Int.
        let json = #"[{"file":"a","line":"42","severity":"low","title":"t","body":"b"},"#
            + #"{"file":"c","line":7,"severity":"low","title":"u","body":"d"}]"#
        let parsed = try FindingsParser.parse(json)
        #expect(parsed.findings.count == 2)
        #expect(parsed.findings[0].line == 42)
        #expect(parsed.findings[1].line == 7)
    }

    @Test("instructions maps to aiInstructions")
    func instructions() throws {
        let json = #"[{"file":"a","severity":"low","title":"t","body":"b","instructions":"do x"}]"#
        let parsed = try FindingsParser.parse(json)
        #expect(parsed.findings[0].aiInstructions == "do x")
    }

    @Test("invalid severity is clamped to medium with a warning")
    func clampSeverity() throws {
        let json = #"[{"file":"a","severity":"critical","title":"t","body":"b"}]"#
        let parsed = try FindingsParser.parse(json)
        #expect(parsed.findings[0].severity == .medium)
        #expect(!parsed.warnings.isEmpty)
    }

    @Test("finding without a file is dropped with a warning")
    func dropNoFile() throws {
        let json = #"[{"severity":"high","title":"t","body":"b"}]"#
        let parsed = try FindingsParser.parse(json)
        #expect(parsed.findings.isEmpty)
        #expect(!parsed.warnings.isEmpty)
    }

    @Test("non-JSON output throws an extraction failure")
    func extractionFailure() {
        #expect(throws: FindingsParser.ExtractionFailure.self) {
            _ = try FindingsParser.parse("the agent said no, sorry")
        }
    }

    @Test("ClaudeRunner unwraps the --output-format json envelope")
    func claudeEnvelope() throws {
        let inner = #"[{\"file\":\"a\",\"severity\":\"low\",\"title\":\"t\",\"body\":\"b\"}]"#
        let envelope = #"{"type":"result","result":"\#(inner)"}"#
        let parsed = try ClaudeRunner().parse(
            AgentOutput(stdout: envelope, stderr: "", exitStatus: 0)
        )
        #expect(parsed.findings.count == 1)
    }

    @Test("ClaudeRunner extracts usage and total_cost_usd from the envelope")
    func claudeEnvelopeUsage() throws {
        let inner = #"[{\"file\":\"a\",\"severity\":\"low\",\"title\":\"t\",\"body\":\"b\"}]"#
        let envelope = """
        {
          "type": "result",
          "result": "\(inner)",
          "total_cost_usd": 0.0123,
          "usage": {
            "input_tokens": 1000,
            "output_tokens": 250,
            "cache_creation_input_tokens": 200,
            "cache_read_input_tokens": 50
          }
        }
        """
        let parsed = try ClaudeRunner().parse(
            AgentOutput(stdout: envelope, stderr: "", exitStatus: 0)
        )
        let usage = try #require(parsed.usage)
        #expect(usage.inputTokens == 1250) // 1000 + 200 + 50
        #expect(usage.outputTokens == 250)
        #expect(usage.totalCostUSD.map { abs($0 - 0.0123) < 0.0001 } == true)
        #expect(usage.source == .agentEnvelope)
    }

    @Test("GeminiRunner unwraps the JSON envelope and parses the fenced response")
    func geminiEnvelope() throws {
        // Gemini wraps the model text in {session_id, response, stats}; the real
        // findings live inside `response` as a ```json fenced block.
        let block = #"{\"findings\":[{\"file\":\"a\",\"severity\":\"low\",\"title\":\"t\",\"body\":\"b\"}]}"#
        let inner = #"```json\n\#(block)\n```"#
        let envelope = #"{"session_id":"x","response":"\#(inner)","stats":{}}"#
        let parsed = try GeminiRunner().parse(
            AgentOutput(stdout: envelope, stderr: "", exitStatus: 0)
        )
        #expect(parsed.findings.count == 1)
        #expect(parsed.findings.first?.file == "a")
    }

    @Test("GeminiRunner falls back to raw stdout when output is not an envelope")
    func geminiPlainOutput() throws {
        let plain = #"{"findings":[{"file":"a","severity":"low","title":"t","body":"b"}]}"#
        let parsed = try GeminiRunner().parse(
            AgentOutput(stdout: plain, stderr: "", exitStatus: 0)
        )
        #expect(parsed.findings.count == 1)
    }

    @Test("ClaudeRunner leaves usage nil when envelope omits accounting fields")
    func claudeEnvelopeNoUsage() throws {
        let inner = #"[{\"file\":\"a\",\"severity\":\"low\",\"title\":\"t\",\"body\":\"b\"}]"#
        let envelope = #"{"type":"result","result":"\#(inner)"}"#
        let parsed = try ClaudeRunner().parse(
            AgentOutput(stdout: envelope, stderr: "", exitStatus: 0)
        )
        #expect(parsed.usage == nil)
    }
}
