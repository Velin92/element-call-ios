//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// Deliberately the only import: this file exists to prove that one import reaches all three
// modules and the core's bindings. Adding `import ElementCallKit` here to fix a build failure would defeat it — fix the
// re-export in Sources/ElementCall instead.
import ElementCall
import Testing

/// The umbrella is a compile-time promise, so these are compile-time assertions that happen to run.
nonisolated struct UmbrellaProductTests {
    @Test
    func reachesEveryModuleThroughOneImport() {
        // ElementCallKit
        #expect(MatrixRTCStreamKind.camera != .screenShare)
        // ElementCallHost
        #expect(ElementCallOptions().isPictureInPictureEnabled)
        // ElementCallUI
        #expect(!ElementCallAccessibilityIdentifiers.minimizedBar.isEmpty)
        // The core's bindings, and with them that a host can implement the backend the stack takes:
        // the protocol comes from the core and the conformance from ElementCallHost, so this only
        // compiles if the umbrella re-exports both.
        let backend: any MatrixBackend = ElementCallFakeMatrixBackend()
        #expect(backend.ownUserId() == "@alice:example.org")
    }
}
