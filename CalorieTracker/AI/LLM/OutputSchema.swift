import Foundation

/// A small schema tree that renders to each provider's dialect. Every property is required and objects are
/// closed, which is what OpenAI strict mode and Anthropic structured outputs need. No nulls and no numeric
/// bounds, because not every provider supports them; range checks happen in `EstimateValidator` instead.
indirect enum SchemaNode: Sendable {
    case string(description: String? = nil, oneOf: [String]? = nil)
    case number(description: String? = nil)
    case array(of: SchemaNode, description: String? = nil)
    case object([(name: String, node: SchemaNode)], description: String? = nil)

    /// Standard JSON Schema, for Anthropic, OpenAI and OpenAI-compatible servers.
    var jsonSchema: JSONValue {
        switch self {
        case .string(let description, let options):
            var value: JSONValue = ["type": "string"]
            if let options { value = value.setting("enum", to: .array(options.map(JSONValue.string))) }
            return value.describing(description)
        case .number(let description):
            return (["type": "number"] as JSONValue).describing(description)
        case .array(let items, let description):
            return (["type": "array", "items": items.jsonSchema] as JSONValue).describing(description)
        case .object(let properties, let description):
            let value: JSONValue = [
                "type": "object",
                "properties": .object(properties.map { .init(key: $0.name, value: $0.node.jsonSchema) }),
                "required": .array(properties.map { .string($0.name) }),
                "additionalProperties": false,
            ]
            return value.describing(description)
        }
    }

    /// Gemini's `responseSchema` (an OpenAPI 3.0 subset): upper-case types, no `additionalProperties`,
    /// and `propertyOrdering` so the reply keeps the order above.
    var geminiSchema: JSONValue {
        switch self {
        case .string(let description, let options):
            var value: JSONValue = ["type": "STRING"]
            if let options {
                value = value.setting("format", to: "enum").setting("enum", to: .array(options.map(JSONValue.string)))
            }
            return value.describing(description)
        case .number(let description):
            return (["type": "NUMBER"] as JSONValue).describing(description)
        case .array(let items, let description):
            return (["type": "ARRAY", "items": items.geminiSchema] as JSONValue).describing(description)
        case .object(let properties, let description):
            let value: JSONValue = [
                "type": "OBJECT",
                "properties": .object(properties.map { .init(key: $0.name, value: $0.node.geminiSchema) }),
                "required": .array(properties.map { .string($0.name) }),
                "propertyOrdering": .array(properties.map { .string($0.name) }),
            ]
            return value.describing(description)
        }
    }
}

struct OutputSchema: Sendable {
    /// Identifier some providers require (letters, digits, underscores).
    let name: String
    let root: SchemaNode
}

private extension JSONValue {
    func describing(_ description: String?) -> JSONValue {
        guard let description else { return self }
        return setting("description", to: .string(description))
    }
}
