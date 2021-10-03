// Just copy and paste the code into a blank playground template
// in Swift Playgrounds app on an iPad or a Mac
// Add an audiofile: press "plus" symbol on the right and choose a file
// !!! Turn off Enable Results in the settings, otherwise you'll get an error !!!
// Created by Roman Gaditskiy: https://GitHub.com/gadirom/Art-in-Swift

import SwiftUI
import PlaygroundSupport
import AVFoundation

let words = ["Satisfy!", "Yeah!", "Come on!"]

var points: [CGPoint] = [
    CGPoint(x: 0, y: 0),
    CGPoint(x: 1, y: 0),
    CGPoint(x: 1, y: 1),
    CGPoint(x: 0, y: 1)
]

struct CrashingButton: View {
    
    var label: String
    
    @State private var cracks: [Triangle] = []
    @State private var d: CGFloat = 0
    
    @State private var tapped = false
    
    var body: some View{
        ZStack{ 
            let a = .pi / CGFloat(cracks.count) * 2
            
            if !tapped{
                Buttons(label: label, tapped: $tapped, crack: TriangleShape(points: points))
                    .frame(width: 100, height: 20)
            }else{ 
            
                ForEach(cracks.indices, id:\.self){id in
                    ZStack{
                        Buttons(label: label, tapped: $tapped, crack: TriangleShape(points: cracks[id]))
                            .frame(width: 200, height: 30)
                    }.offset(x: d*cos(CGFloat(id+1)*a), y: d*sin(CGFloat(id+1)*a))
                }
            }
        }.onAppear(){
            cracks = createCracks(n: Int.random(in: 4...5))
        }
        .onChange(of: tapped){_ in withAnimation(.easeOut(duration: 1), {d = 5})}
    }
}

struct TriangleShape: Shape {
    
    let points: [CGPoint]
    
    func path(in rect: CGRect) -> Path {
        
        Path { path in
            let p = points.map(){CGPoint(x: $0.x * rect.width, y: $0.y * rect.height)}
            path.addLines( p )
            path.closeSubpath()
        }
    }
}
struct Buttons: View {
    
    init(label: String, tapped: Binding<Bool>, crack: TriangleShape){
        self.label = label
        self._tapped = tapped
        self.crack = crack
    }
    
    var label : String
    var crack : TriangleShape
    
    @Binding var tapped: Bool
    @State var pressed: Bool = false
    
    var body: some View {
        
        VStack{   
            Text(label)
                .foregroundColor(Color.black)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .blur(radius: 0.4)
                .frame(width:200, height: 60)
                .background(
                    ZStack{ 
                        Color(#colorLiteral(red: 0.8407290577888489, green: 0.8310598731040955, blue: 0.9999999403953552, alpha: 1.0))
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .foregroundColor(.white)
                            .blur(radius: 10)
                            .offset(x: -8, y: -8)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(gradient: Gradient(colors: [Color(#colorLiteral(red: 0.8293229937553406, green: 0.8711527585983276, blue: 1.000000238418579, alpha: 1.0)),Color.white]), startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .padding(2)
                            .blur(radius: 4)
                    }
                )
                .clipShape(crack)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color(#colorLiteral(red: 0.6431992650032043, green: 0.6481773853302002, blue: 1.0000001192092896, alpha: 1.0)), radius: pressed ? 5 : 20, 
                        x: pressed ? 3 : 20, y: pressed ? 3 : 20)
                .shadow(color: Color(#colorLiteral(red: 0.9999160170555115, green: 1.0000032186508179, blue: 0.9998849034309387, alpha: 1.0)), radius: pressed ? 5 : 20,
                        x: pressed ? -5 : -20, y: pressed ? -5 : -20)
                .scaleEffect(pressed ? 0.9 : 1)
                .onTapGesture(count: 1){  
                    withAnimation(.easeInOut(duration: 1.2)){pressed = true}
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1){tapped = true; playSound()}
                }
                .onAppear(){ pressed = tapped}
        }
    }
}

typealias Triangle = [CGPoint]

func createCracks(n: Int) -> [Triangle]{
    
    var a: [Double] = Array(repeating: 1, count: n)
    a = a.map{ _ in Double.random(in: 1...10)}
    
    let sum = a.reduce(0) {$0 + $1}
    a = a.map{ $0 / sum * .pi * 2}
    
    let c = CGPoint(x: 0.5, y: 0.5)
    var a0: Double = a.last!
    
    var triangles: [Triangle] = []
    for a1 in a {
        let t = [c,
                 rotate(a0)+c,
                 rotate(a0 + a1)+c]
        a0 += a1
        triangles.append(t)
    }
    return triangles
}

func rotate(_ a: Double) -> CGPoint{
    return CGPoint(x: cos(a) * 2, y: sin(a) * 2)
}

extension CGPoint{
    static func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint{
        CGPoint(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }
}

var audioPlayer: AVAudioPlayer?

func playSound() {
    do {
        let audioFile = #fileLiteral(resourceName: "Wine-Glass-Shatering-A1-www.fesliyanstudios.com.mp3") // << --- Add a sound here!
        
        audioPlayer = try AVAudioPlayer(contentsOf: audioFile)
        audioPlayer?.play()
    } catch {
        print("ERROR: Can't initialize audioPlayer")
    }
    
}

struct ContentView: View {
    var body: some View{
        ZStack{
            Color(#colorLiteral(red: 0.8903511166572571, green: 0.8643324971199036, blue: 1.0000003576278687, alpha: 1.0))
            VStack{
                ForEach(words.indices, id: \.self){id in 
                    CrashingButton(label: words[id]).frame(width: 300, height: 100)
                }
            }
        }.frame(maxWidth:.infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
    }
}

PlaygroundPage.current.setLiveView(ContentView())
