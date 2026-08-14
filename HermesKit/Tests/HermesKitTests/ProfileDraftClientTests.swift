import Foundation
import Testing

@testable import HermesKit

struct ProfileDraftClientTests {
  @Test func liveStoreScopesDraftsByServerAndProfile() {
    let suiteName = "ProfileDraftClientTests.scope.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let client = ProfileDraftClient.live(defaults: defaults)
    let first = URL(string: "https://first.example")!
    let second = URL(string: "https://second.example")!

    client.save(first, "work", Data("first-work".utf8))
    client.save(first, "default", Data("first-default".utf8))
    client.save(second, "work", Data("second-work".utf8))

    #expect(client.load(first, "work") == Data("first-work".utf8))
    #expect(client.load(first, "default") == Data("first-default".utf8))
    #expect(client.load(second, "work") == Data("second-work".utf8))
  }

  @Test func removeOnlyClearsTheRequestedDraft() {
    let client = ProfileDraftClient.inMemory()
    let server = URL(string: "https://agent.example")!
    client.save(server, "default", Data("default".utf8))
    client.save(server, "work", Data("work".utf8))

    client.remove(server, "work")

    #expect(client.load(server, "work") == nil)
    #expect(client.load(server, "default") == Data("default".utf8))
  }

  @Test func removeAllClearsEveryDraft() {
    let client = ProfileDraftClient.inMemory()
    let first = URL(string: "https://first.example")!
    let second = URL(string: "https://second.example")!
    client.save(first, "work", Data("first".utf8))
    client.save(second, "work", Data("second".utf8))

    client.removeAll()

    #expect(client.load(first, "work") == nil)
    #expect(client.load(second, "work") == nil)
  }
}
