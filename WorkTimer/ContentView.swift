//
//  ContentView.swift
//  WorkTimer
//
//  Created by Ally leandre on 25/10/2026.
//

import SwiftUI

/// Temporary placeholder until the designed screens land in Phase 3.
struct ContentView: View {
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        Text("WorkTimer · \(String(describing: engine.state.phase))")
            .padding()
    }
}
