// DS4ControllerArtwork.swift — Controller photo background.
// Loads the DS4 controller photo from the asset catalog.
// No observable dependencies — never redraws on state changes.

import SwiftUI

struct DS4ControllerArtwork: View {
    var body: some View {
        Image("DS4Controller")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: DS4Layout.canvasWidth, height: DS4Layout.canvasHeight)
    }
}

#Preview("DS4 Controller Artwork") {
    DS4ControllerArtwork()
        .padding()
        .background(.black)
}
