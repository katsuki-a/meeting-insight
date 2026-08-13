import Foundation
import XCTest
@testable import MeetingInsightDomain

final class InsightCardContractTests: XCTestCase {
    func testValidFixtureDecodesAndReencodesSemantically() throws {
        let fixture = try validFixtureData()

        let card = try InsightCardCoding.decoder().decode(AgentInsightCard.self, from: fixture)
        let encoded = try InsightCardCoding.encoder().encode(card)

        XCTAssertEqual(card.schemaVersion, 1)
        XCTAssertEqual(card.verdict, .verified)
        XCTAssertEqual(try jsonObject(from: encoded), try jsonObject(from: fixture))
    }

    func testUnknownVerdictIsRejected() throws {
        let data = try mutatedFixture { root in
            root["verdict"] = "probably_true"
        }

        XCTAssertThrowsError(try InsightCardCoding.decoder().decode(AgentInsightCard.self, from: data))
    }

    func testMissingRequiredFieldIsRejected() throws {
        let data = try mutatedFixture { root in
            root.removeValue(forKey: "answer")
        }

        XCTAssertThrowsError(try InsightCardCoding.decoder().decode(AgentInsightCard.self, from: data))
    }

    func testAdditionalTopLevelFieldIsRejected() throws {
        let data = try mutatedFixture { root in
            root["unexpected"] = true
        }

        XCTAssertThrowsError(try InsightCardCoding.decoder().decode(AgentInsightCard.self, from: data))
    }

    func testAdditionalNestedFieldIsRejected() throws {
        let data = try mutatedFixture { root in
            var scope = try XCTUnwrap(root["scope"] as? [String: Any])
            scope["absolute_path"] = "/private/repository"
            root["scope"] = scope
        }

        XCTAssertThrowsError(try InsightCardCoding.decoder().decode(AgentInsightCard.self, from: data))
    }

    func testBundledSchemaMatchesCanonicalSchema() throws {
        let canonical = try Data(contentsOf: canonicalSchemaURL())
        let bundled = try InsightCardSchema.data()

        XCTAssertEqual(try jsonObject(from: bundled), try jsonObject(from: canonical))
    }

    func testSchemaDescribesSwiftContractVersionAndEnums() throws {
        let schema = try XCTUnwrap(try jsonObject(from: InsightCardSchema.data()) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let required = try XCTUnwrap(schema["required"] as? [String])
        let schemaVersion = try XCTUnwrap(properties["schema_version"] as? [String: Any])
        let verdict = try XCTUnwrap(properties["verdict"] as? [String: Any])

        XCTAssertEqual(Set(properties.keys), AgentInsightCard.schemaPropertyNames)
        XCTAssertEqual(Set(required), AgentInsightCard.requiredSchemaPropertyNames)
        XCTAssertEqual(schemaVersion["const"] as? Int, InsightCardSchema.version)
        XCTAssertEqual(
            Set(try XCTUnwrap(verdict["enum"] as? [String])),
            Set(Verdict.allCases.map(\.rawValue))
        )

        let scopeProperties = try nestedProperties(in: properties, key: "scope")
        XCTAssertEqual(
            Set(scopeProperties.keys),
            ["environment", "repositories", "knowledge_roots", "production_revision_verified"]
        )
        let repositoryProperties = try itemProperties(in: scopeProperties, key: "repositories")
        XCTAssertEqual(Set(repositoryProperties.keys), ["name", "commit_sha", "dirty_worktree"])
        let knowledgeProperties = try itemProperties(in: scopeProperties, key: "knowledge_roots")
        XCTAssertEqual(Set(knowledgeProperties.keys), ["name", "revision", "revision_kind"])
        XCTAssertEqual(
            try enumValues(in: knowledgeProperties, key: "revision_kind"),
            Set(KnowledgeRevisionKind.allCases.map(\.rawValue))
        )

        let claimProperties = try itemProperties(in: properties, key: "claims")
        XCTAssertEqual(Set(claimProperties.keys), ["text", "kind", "confidence", "evidence"])
        XCTAssertEqual(
            try enumValues(in: claimProperties, key: "kind"),
            Set(InsightClaimKind.allCases.map(\.rawValue))
        )
        let evidenceProperties = try itemProperties(in: claimProperties, key: "evidence")
        XCTAssertEqual(
            Set(evidenceProperties.keys),
            [
                "source_type", "source_name", "source_revision", "path", "line_start", "line_end",
                "quote", "quote_sha256", "url", "retrieved_at"
            ]
        )
        XCTAssertEqual(
            try enumValues(in: evidenceProperties, key: "source_type"),
            Set(EvidenceSourceType.allCases.map(\.rawValue))
        )
    }

    private func validFixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "valid-insight-card", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func mutatedFixture(_ mutation: (inout [String: Any]) throws -> Void) throws -> Data {
        var root = try XCTUnwrap(try jsonObject(from: validFixtureData()) as? [String: Any])
        try mutation(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func jsonObject(from data: Data) throws -> AnyHashable {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? AnyHashable)
    }

    private func nestedProperties(
        in properties: [String: Any],
        key: String
    ) throws -> [String: Any] {
        let object = try XCTUnwrap(properties[key] as? [String: Any])
        return try XCTUnwrap(object["properties"] as? [String: Any])
    }

    private func itemProperties(
        in properties: [String: Any],
        key: String
    ) throws -> [String: Any] {
        let array = try XCTUnwrap(properties[key] as? [String: Any])
        let items = try XCTUnwrap(array["items"] as? [String: Any])
        return try XCTUnwrap(items["properties"] as? [String: Any])
    }

    private func enumValues(
        in properties: [String: Any],
        key: String
    ) throws -> Set<String> {
        let property = try XCTUnwrap(properties[key] as? [String: Any])
        return Set(try XCTUnwrap(property["enum"] as? [String]))
    }

    private func canonicalSchemaURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Schemas/insight-card.schema.json")
    }
}
