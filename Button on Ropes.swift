
// Just copy and paste the code into a blank playground template
// in Swift Playgrounds app on an iPad or a Mac
// !!! Turn off Enable Results in the settings, otherwise you'll get an error !!!
// Created by Roman Gaditskiy: https://GitHub.com/gadirom/Art-in-Swift

import SwiftUI
import PlaygroundSupport
import Combine
import simd

let gravity : CGFloat = 0.04
let initHeight: CGFloat = 600

let refreshRate = 120
let refreshInterval = 1 / refreshRate
let timer = Timer.publish(every: TimeInterval(refreshInterval), tolerance: 0, on: .current, in: .common).autoconnect()
var startTime = Date()

struct Point{
    init(current: CGPoint, former: CGPoint, locked: Bool){
        self.current = current
        self.former = former
        self.locked = locked
    }
    var current = CGPoint()
    var former = CGPoint()
    var locked = false
}

struct Segment : Identifiable{
    var id:Int
    var a:Int
    var b:Int
    var l:CGFloat
}

struct Rope{
    var segments:[Segment] = []
    var points:[Point] = []
    var button = -1
    
    init(numberOfSegments: Int){
        points = (0..<numberOfSegments+1).indices.map{
            let n = $0 <= numberOfSegments/2 ? 0 : 1
            let k = CGFloat($0 * (1-n*2) + n*numberOfSegments)
            let p = CGPoint(x: CGFloat(-150 + n*300),
                            y: k*10 + initHeight)
            return Point(current: p, former: p, locked: k==0 )
        }
        segments = (0..<numberOfSegments).indices.map{
            Segment(id:$0, a: $0, b: $0+1, l: (points[$0].current - points[$0+1].current).length())}
        button = numberOfSegments/2  
    }
    mutating func simulate(time:CGFloat) {
        points = points.map{ p in
            var p = p
            let former = p.current
            if !p.locked{
                p.current = p.current +
                    (p.current - p.former) +
                    (CGSize(width: 0, height: 1) * time * time * gravity)
                p.former = former
            }
            return p
        }
        for _ in 0...5{
            segments = segments.map { s in
                var a = points[s.a].current
                var b = points[s.b].current
                let aLocked = points[s.a].locked
                let bLocked = points[s.b].locked
                
                let sc = (a + b) / 2.0 //center
                let sd = (a - b).normalized() //direction
                let l = (a - b).length()
                
                if l > s.l {
                    if (!aLocked)
                    {
                        a = sc + sd * s.l / 2
                    }
                    if (!bLocked)
                    {
                        b = sc - sd * s.l / 2
                    }
                }
                points[s.a].current = a
                points[s.b].current = b
                return s
            }
        }
    }
}

struct ButtonView: View{
    
    var action: () -> Void
    
    var body: some View{
        Button(action: action) {
            HStack {
                Image(systemName: "trash.fill")
                    .font(.title)
                Text("Yeah!")
                    .fontWeight(.semibold)
                    .font(.title)
                    .frame(width: 300)
            }
            .padding()
            .foregroundColor(.white)
            .background(Color.red)
            .cornerRadius(10)
        }
    }
}

struct RopeView: View {
    
    init(rope: Binding<Rope>, newColor: Binding<Color>, newOffset: Binding<CGFloat>){
        self._rope = rope
        self._newColor = newColor
        self._newOffset = newOffset
    }
    
    @Binding var rope: Rope
    @Binding var newColor: Color
    @Binding var newOffset: CGFloat
    
    @State var angle : Double = 0
    @State var currentAngle : Double = 0
    
    var body: some View{
        ZStack{
            let p = rope.points
            ForEach(rope.segments){ s in
                let pp = p[s.b].current - p[s.a].current
                let of = (pp / 2) + CGSize(p: p[s.a].current)
                if s.id != rope.button{
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: pp.length() + 5, height: 5)
                        .rotationEffect(Angle(radians: atan(Double(pp.height/pp.width))))
                        .offset(of)
                }
            }.shadow(radius: 5)
            
            let s = rope.segments.first(where: {$0.id == rope.button})!
            let pp = p[s.b].current - p[s.a].current
            let of = (pp / 2) + CGSize(p: p[s.a].current)
            ButtonView(){
                rope.segments.remove(at: Int(Double(rope.segments.count)*(0.25)))
                DispatchQueue.main.asyncAfter(deadline: .now()+0.6){
                    rope.segments.remove(at: Int(Double(rope.segments.count)*(0.75)))
                }
                DispatchQueue.main.asyncAfter(deadline: .now()+0.5){ 
                    withAnimation(){newColor = .white}
                    newOffset = -600
                }
            }
            .rotationEffect(Angle(radians: angle))
            .offset(CGSize(width:of.width, height:of.height+30))
            .shadow(radius: 7)
            
        }.onReceive(timer) { time in
            rope.simulate(time: CGFloat(time.compare(startTime).rawValue))
            
            let p = rope.points
            let s = rope.segments.first(where: {$0.id == rope.button})!
            let pp = p[s.b].current - p[s.a].current
            let delta = atan(Double(pp.height/pp.width)) - currentAngle
            currentAngle += delta
            angle += abs(delta) > .pi/2 ? (abs(delta) - .pi)*sign(delta) : delta
        }
    }
}

struct ContentView: View {
    
    @State var rope = Rope(numberOfSegments: 51)
    
    @State var simulation = true
    @State var offset = initHeight
    @State var newOffset = initHeight
    
    @State var color = Color.white
    
    var body: some View{
        ZStack{
            color
            
            ZStack{
                ZStack{ 
                    RoundedRectangle(cornerSize: CGSize(width: 10, height: 10))
                        .fill(Color.blue)
                        .frame(width: 400, height: 400)
                        .shadow(radius: 5)
                    Text("Are you sure?")
                        .foregroundColor(.black)
                        .fontWeight(.semibold)
                        .font(.title)
                        .offset(x: 0, y: -50)
                }.offset(x: 0, y: offset)
                RopeView(rope: $rope,newColor: $color, newOffset: $newOffset)
                    .offset(x: 0, y: -150)
            }
        }.frame(maxWidth:.infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        
        .onAppear(){
            startTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1){ 
                newOffset = .zero
                withAnimation(){color = Color(#colorLiteral(red: 0.002523967530578375, green: -5.7450830354355276e-05, blue: 0.38279783725738525, alpha: 1.0))}
            }
        }
        .onReceive(timer) { time in
            
            offset += CGFloat(sign(Float(newOffset - offset)))*4
            rope.points[0].current = CGPoint(x: -150, y: offset)
            rope.points[rope.points.count-1].current = CGPoint(x: 150, y: offset)
        }
    }
}

extension CGPoint{
    static func +(lhs: CGPoint, rhs: CGSize) -> CGPoint{
        CGPoint(
            x: lhs.x + rhs.width,
            y: lhs.y + rhs.height
        )
    }
    
    static func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint{
        CGPoint(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }
    
    static func +=(lhs: inout CGPoint, rhs: CGPoint) {
        lhs = CGPoint(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }
    
    static func -(lhs: CGPoint, rhs: CGSize) -> CGPoint{
        CGPoint(
            x: lhs.x - rhs.width,
            y: lhs.y - rhs.height
        )
    }
    
    static func -(lhs: CGPoint, rhs: CGPoint) -> CGSize{
        CGSize(
            width: lhs.x - rhs.x,
            height: lhs.y - rhs.y
        )
    }
    
    static func  /(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x / rhs,
                y: lhs.y / rhs)
    }
    
    func length() -> CGFloat{
        sqrt(x * x + y * y)
    }
    
    func normalized() -> CGPoint {
        let len = length()
        return len>0 ? self / len : .zero
    }
}

extension CGSize{
    
    init(p: CGPoint){
        self.init(width:p.x, height:p.y)
    }
    
    func length() -> CGFloat{
        sqrt(width * width + height * height)
    }
    
    func normalized() -> CGSize {
        let len = length()
        return len>0 ? self / len : .zero
    }
    
    static func +=(lhs: inout CGSize, rhs: CGSize) {
        lhs = CGSize(
            width: lhs.width + rhs.width,
            height: lhs.height + rhs.height
        )
    }
    
    static func +(lhs: CGSize, rhs: CGSize) -> CGSize{
        CGSize(
            width: lhs.width + rhs.width,
            height: lhs.height + rhs.height
        )
    }
    
    static func -(lhs: CGSize, rhs: CGSize) -> CGSize{
        CGSize(
            width: lhs.width - rhs.width,
            height: lhs.height - rhs.height
        )
    }
    
    static func  *(lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs,
               height: lhs.height * rhs)
    }
    
    static func  +(lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width + rhs,
               height: lhs.height + rhs)
    }
    
    static func  /(lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width / rhs,
               height: lhs.height / rhs)
    }
}

PlaygroundPage.current.setLiveView(ContentView())
