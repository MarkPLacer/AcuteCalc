import SwiftUI

/// Nastavitve › Licence: code by others in the app and its licence. The Turbo colour map that colours 3D
/// surfaces by height (`turbo()` in Surface3D.metal) is Apache-2.0, whose section 4(a) asks that everyone who
/// gets the app also gets a copy of the licence. The text is bundled unchanged (Apache-2.0.txt, from
/// https://www.apache.org/licenses/LICENSE-2.0.txt) and shown offline.
struct LicensesView: View {
    /// The bundled licence text; nil only if the file were missing from the app.
    static let apacheLicense: String? = Bundle.main.url(forResource: "Apache-2.0", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    /// The notice at the top of the original, https://gist.github.com/mikhailov-work/0d177465a8151eb6ede1768d51d476c7.
    static let turboNotice = """
        Copyright 2019 Google LLC.
        SPDX-License-Identifier: Apache-2.0
        Polynomial approximation in GLSL for the Turbo colormap
        Original LUT: https://gist.github.com/mikhailov-work/ee72ba4191942acecc03fe6da94fc73f
        Authors:
        Colormap Design: Anton Mikhailov (mikhailov@google.com)
        GLSL Approximation: Ruofei Du (ruofei@google.com)
        https://gist.github.com/mikhailov-work/0d177465a8151eb6ede1768d51d476c7
        """

    var body: some View {
        Form {
            Section {
                Text("3D ploskve so po višini obarvane s polinomskim približkom barvne lestvice Turbo, prenesenim iz GLSL v Metal.")
                Text(verbatim: Self.turboNotice)
                    .font(.footnote)
            } header: {
                Text("Barvna lestvica Turbo")
            } footer: {
                Text("Zanj velja licenca Apache 2.0; njeno besedilo je spodaj.")
            }
            Section("Apache License 2.0") {
                Text(Self.apacheLicense ?? "https://www.apache.org/licenses/LICENSE-2.0")
                    .font(.footnote)
            }
        }
        .navigationTitle("Licence")
        .navigationBarTitleDisplayMode(.inline)
    }
}
