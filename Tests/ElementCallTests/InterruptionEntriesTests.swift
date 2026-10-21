//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallHost
import ElementCallKit
@testable import ElementCallUI
import Foundation
import Testing

/// The core's causes grouped into the list's three entries (034 R13, R23, R29, R38).
@Suite("Interruption entries")
struct InterruptionEntriesTests {
    private let outage = MatrixRTCSignallingHealth.unreachable(since: Date(timeIntervalSince1970: 100))
    
    @Test
    func nothingInterruptedIsNoEntry() {
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: .none).isEmpty)
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: nil).isEmpty)
    }
    
    /// Before media there is no record, and the server is the one cause that can already be known.
    @Test
    func theServerEntryNeedsNoMedia() {
        #expect(ElementCallInterruption.entries(signalling: outage, record: nil)
            == [.ownServer(isMembershipLapsed: false)])
    }
    
    @Test
    func eachSideIsItsOwnEntryInOrder() {
        let record = MatrixRTCInterruptions(signalling: outage,
                                            isOwnMembershipLapsed: true,
                                            ownMedia: .reconnecting,
                                            membersUnreachable: ["@bob:x:B"],
                                            undecryptable: ["@carol:x:C"],
                                            unmappable: ["PA_xyz"])
        
        #expect(ElementCallInterruption.entries(signalling: outage, record: record)
            == [.ownServer(isMembershipLapsed: true), .ownMedia, .othersMedia])
    }
    
    /// They get no tile and none of our keys, so there is nothing to tell the user, outage or not.
    @Test
    func anUnmappableParticipantAloneIsNoEntry() {
        let record = MatrixRTCInterruptions(unmappable: ["PA_xyz"])
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: record).isEmpty)
    }
    
    /// Signalling back is not the republish landed: the others still cannot see us until it does.
    @Test
    func aLapseOutlivesTheOutage() {
        let record = MatrixRTCInterruptions(isOwnMembershipLapsed: true)
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: record)
            == [.ownServer(isMembershipLapsed: true)])
    }
    
    @Test
    func anyMemberCauseIsTheOthersEntry() {
        for record in [MatrixRTCInterruptions(membersReconnecting: ["a"]),
                       MatrixRTCInterruptions(membersUnreachable: ["a"]),
                       MatrixRTCInterruptions(undecryptable: ["a"])] {
            #expect(ElementCallInterruption.entries(signalling: .reachable, record: record) == [.othersMedia])
        }
    }
    
    /// A member undecryptable for a moment is the key rotation every join and leave makes, not an
    /// interruption.
    @Test
    func aMemberWithinTheKeyGraceIsNotYetUndecryptable() {
        let record = MatrixRTCInterruptions(undecryptable: ["brief", "long"])
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: record, withinKeyGrace: ["brief"]) == [.othersMedia])
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: record, withinKeyGrace: ["brief", "long"]).isEmpty)
    }
    
    @Test
    func ourOwnMediaUnreachableIsStillOurEntry() {
        let record = MatrixRTCInterruptions(ownMedia: .unreachable)
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: record) == [.ownMedia])
    }
    
    /// The core reports the first connection to our SFU as a reconnection (C11).
    @Test
    func theFirstConnectionIsNoInterruption() {
        let record = MatrixRTCInterruptions(ownMedia: .reconnecting, membersReconnecting: ["@bob:x:B"])
        #expect(ElementCallInterruption.entries(signalling: outage, record: record, hasMediaConnected: false)
            == [.ownServer(isMembershipLapsed: false), .othersMedia])
    }
}

/// What an interruption disables, and what it never does (034 R15).
@Suite("Interrupted controls")
@MainActor
struct InterruptedControlsTests {
    typealias Fixtures = ElementCallPreviewFixtures
    
    @Test
    func theHandWaitsForOurServer() {
        var state = Fixtures.connected(tiles: Fixtures.group)
        #expect(state.isHandControlEnabled)
        state.isSignallingReachable = false
        #expect(!state.isHandControlEnabled)
    }
    
    /// A share in progress can always be stopped; only starting one needs our media server.
    @Test
    func onlyStartingAShareWaitsForOurMediaServer() {
        var state = Fixtures.connected(tiles: Fixtures.group, isScreenSharingEnabled: true)
        state.isOwnMediaReconnecting = true
        #expect(!state.isScreenShareControlEnabled)
        state.isScreenSharing = true
        #expect(state.isScreenShareControlEnabled)
    }
}

/// What a tile shows while its media does not arrive (034 R23, R29, R33, R34, C6).
@Suite("Interrupted tiles")
@MainActor
struct InterruptedTileTests {
    private func tiles(_ remote: MatrixRTCTile, own: MatrixRTCTile? = nil, withinKeyGrace: Set<String> = []) -> [ElementCallTile] {
        ElementCallScreenViewModel.tiles(roster: MatrixRTCTileRoster([remote]),
                                         own: own,
                                         profiles: [:],
                                         youLabel: "You",
                                         isLocalMicrophoneMuted: false,
                                         localHasVideo: true,
                                         withinKeyGrace: withinKeyGrace)
    }
    
    private func bob(connection: MatrixRTCConnectionState = .connected, isDecryptable: Bool = true) -> MatrixRTCTile {
        MatrixRTCTile(id: MatrixRTCTileID(memberID: "@bob:x:B"), userID: "@bob:x", hasVideo: true, connection: connection, isDecryptable: isDecryptable)
    }
    
    @Test
    func eachCauseIsTheTilesState() {
        #expect(tiles(bob()).first?.mediaState == .live)
        #expect(tiles(bob(connection: .reconnecting)).first?.mediaState == .reconnecting)
        #expect(tiles(bob(connection: .unreachable)).first?.mediaState == .reconnecting)
        #expect(tiles(bob(isDecryptable: false)).first?.mediaState == .undecryptable)
    }
    
    /// Nothing decrypts over a connection that is down, so the connection is the one to say.
    @Test
    func aLostConnectionWinsOverDecryption() {
        #expect(tiles(bob(connection: .reconnecting, isDecryptable: false)).first?.mediaState == .reconnecting)
    }
    
    /// Every join and leave rotates the keys, and for a moment frames come under a key we lack.
    @Test
    func aMemberWithinTheKeyGraceIsNotUndecryptableYet() {
        #expect(tiles(bob(isDecryptable: false), withinKeyGrace: ["@bob:x:B"]).first?.mediaState == .live)
        #expect(tiles(bob(connection: .reconnecting), withinKeyGrace: ["@bob:x:B"]).first?.mediaState == .reconnecting)
    }
    
    @Test
    func ourOwnTileCarriesOurMediaServer() {
        let own = MatrixRTCTile(id: MatrixRTCTileID(memberID: "@me:x:M"), userID: "@me:x", isLocal: true, hasVideo: true, connection: .reconnecting)
        let mine = tiles(bob(), own: own).first
        #expect(mine?.isLocal == true)
        #expect(mine?.mediaState == .reconnecting)
        // Our picture is the camera in our hand, so it is never gated off.
        #expect(mine?.hasVideo == true)
    }
}

/// What the list says (034 R13, R17).
@Suite("Interruption text")
struct InterruptionTextTests {
    private let strings = ElementCallStrings()
    
    @Test
    func theLapseChangesTheServerEntryRatherThanAddingOne() {
        #expect(strings.text(for: .ownServer(isMembershipLapsed: false)) == strings.ownServerUnreachable)
        #expect(strings.text(for: .ownServer(isMembershipLapsed: true)) == strings.ownServerLapsed)
    }
}
