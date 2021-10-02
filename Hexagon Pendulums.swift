// Just copy and paste the code into a blank playground template
// in Swift Playgrounds app on an iPad or a Mac
// !!! Turn off Enable Results in the settings, otherwise you'll get an error !!!
// Created by Roman Gaditskiy: https://GitHub.com/gadirom/Art-in-Swift

import SwiftUI
import PlaygroundSupport
import UIKit

let screenSize = UIScreen.main.bounds

let scaleFactor = CGSize(
    width:screenSize.width / 4.5,
    height:screenSize.height / 2.8) 
let cellWidth : CGFloat = 55
let cellHeight = cellWidth
let angleRadius : CGFloat = 5//rounded corners
let cellSpacing : CGFloat = 5
let cellCount = 97
let rowWidth = 8 //width of the grid

struct Cell {
    var angle: Double = 90
    var selection: Int = 0
}

let palette: [Color] = [.gray, .blue, .red, .purple, .yellow]

struct Game: View {
    
    @State private var offset = CGSize.zero
    @State private var idDragged = -1
    @State private var idSelected = -1
    @State private var selectedX = -1
    @State private var selectedY = -1
    @State private var draggedValue = 0
    @State private var gestureLocation = CGSize.zero
    
    @State private var currentAmount: CGFloat = 0
    @State private var finalAmount: CGFloat = 1
    
    var data: [Int] = Array.init(repeating: 0, count: cellCount)
    
    //the grid
    @State private var rows : [[Cell]] = []
    
    @State var scale : CGFloat = 1.0
    
    var body: some View{
        
        ZStack{ 
            //the grid
            GridView(rows: $rows)
            
        }.scaledToFill()
        .background(Color.white)
        .scaleEffect(finalAmount + currentAmount)
        .animation(.easeInOut(duration: 1), value:currentAmount)
        .gesture(magnificationGesture)
        .onAppear(perform: {generateHoney()})
        
        .drawingGroup()
    }
    
    //Magnification gesture - for view
    var magnificationGesture : some Gesture{ 
        MagnificationGesture()
        .onChanged { amount in
            let newAmount = (amount - 1) * (currentAmount + finalAmount)
            if finalAmount + newAmount >= 1 && finalAmount + newAmount <= 50 { 
                currentAmount = newAmount
            }
        }
        .onEnded { amount in
            finalAmount += currentAmount
            currentAmount = 0
        }
    }
    
    // generating HoneyComb Rows.....
    func generateHoney(){
        
        var count = 0
        var generated : [Cell] = []
        
        for _ in 0..<cellCount{
            let a: Double = 1.5 //Double(generated.count)-(Double(rowWidth)-0.5)/2
            generated.append(Cell(angle: generated.count % 2 == 0 ? 20 * a : -20 * a))
            // creating rows...
            if generated.count == rowWidth - 1 {
                if let last = rows.last{
                    if last.count == rowWidth {
                        rows.append(generated)
                        generated.removeAll()
                    }
                }
                if rows.isEmpty{
                    rows.append(generated)
                    generated.removeAll()
                }
            }
            if generated.count == rowWidth {
                rows.append(generated)
                generated.removeAll()
            }
            count += 1
            if count == cellCount && !generated.isEmpty{
                rows.append(generated)
            }
        }
    }
}

struct GridView: View {
    
    @Binding var rows : [[Cell]]
    
    @State var selection = 0
    @State var selectedCount = 0
    
    public init(rows: Binding<[[Cell]]>){
        self._rows = rows
    }
    
    var body: some View {
        VStack(spacing: CGFloat(-cellWidth/4) + cellSpacing){
            
            ForEach(rows.indices,id: \.self){index in
                
                HStack(spacing: cellSpacing){
                    
                    EnumeratedForEach(rows[index]){idx, cell in
                        CellObject(idx:idx, idy:index, angle: cell.angle,
                                   selection: cell.selection)
                            .onTapGesture {
                                select(index: index, idx: idx, selection: selection, deep: 0)
                                selection += 1
                                if selection == palette.count {selection = 0}
                            }
                    }
                }
            }
        }
    }
    
    func select(index: Int, idx: Int, selection: Int, deep: Int){
        if rows[index][idx].selection == selection || deep > rows.count {return}
        let deep = deep + 1
        withAnimation(){rows[index][idx].selection = selection}
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1 ){ 
            
            if idx > 0 {
                select(index: index, idx: idx-1, selection: selection, deep: deep)
            }
            if index % 2 != 0{
                if idx < rowWidth-1{ 
                    select(index: index, idx: idx+1, selection: selection, deep: deep)
                }
                if index > 0 && idx > 0{ 
                    select(index: index-1, idx: idx-1, selection: selection, deep: deep)
                }
                if index < rows.count-1 && idx > 0 { 
                    select(index: index+1, idx: idx-1, selection: selection, deep: deep)
                }
                if idx < rowWidth - 2{ 
                    if index > 0 { 
                        select(index: index-1, idx: idx, selection: selection, deep: deep)
                    }
                    if index < rows.count-1 { 
                        select(index: index+1, idx: idx, selection: selection, deep: deep)
                    }
                }
            }else{
                if idx < rowWidth-2{ 
                    select(index: index, idx: idx+1, selection: selection, deep: deep)
                }
                if index > 1 { 
                    select(index: index-1, idx: idx, selection: selection, deep: deep)
                }
                if index < rows.count-2 { 
                    select(index: index+1, idx: idx, selection: selection, deep: deep)
                }
                if index > 0{ 
                    select(index: index-1, idx: idx+1, selection: selection, deep: deep)
                }
                if index < rows.count-1{ 
                    select(index: index+1, idx: idx+1, selection: selection, deep: deep)
                }
            }
        }
    }
}

struct CellObject: View {
    
    var idx: Int
    var idy: Int
    var angle: Double
    var selection: Int
    
    var body: some View {
        ZStack{ 
            Hexagon(angleRadius: angleRadius)
                .fill(palette[selection])
                .shadow(radius: 3)
                .frame(width: cellWidth, height: cellHeight)
            Pendulum(height: cellWidth/2, width: cellWidth/6, radius: cellWidth/5, period: 1, angle: Double((selection*selection))*angle)
                .frame(width: cellWidth, height: cellHeight)
        }
    }
}

struct Hexagon: Shape {
    
    let angleRadius : CGFloat 
    
    func path(in rect: CGRect) -> Path {
        
        return Path { path in
            
            let pt1 = CGPoint(x: 0, y: rect.height / 4)
            let pt2 = CGPoint(x: 0, y: rect.height - rect.height / 4)
            let pt3 = CGPoint(x: rect.width / 2, y: rect.height)
            let pt4 = CGPoint(x: rect.width, y: rect.height - rect.height / 4)
            let pt5 = CGPoint(x: rect.width, y: rect.width / 4)
            let pt6 = CGPoint(x: rect.width / 2, y: 0)
            
            path.move(to: pt6)
            
            path.addArc(tangent1End: pt1, tangent2End: pt2, radius: angleRadius)
            path.addArc(tangent1End: pt2, tangent2End: pt3, radius: angleRadius)
            path.addArc(tangent1End: pt3, tangent2End: pt4, radius: angleRadius)
            path.addArc(tangent1End: pt4, tangent2End: pt5, radius: angleRadius)
            path.addArc(tangent1End: pt5, tangent2End: pt6, radius: angleRadius)
            path.addArc(tangent1End: pt6, tangent2End: pt1, radius: angleRadius)
        }
    }
    init(angleRadius :CGFloat){
        self.angleRadius = angleRadius
    }
}

// a struct that does the same thing as "ForEach" but gets index along with the item 
struct EnumeratedForEach<ItemType, ContentView: View>: View {
    let data: [ItemType]
    let content: (Int, ItemType) -> ContentView
    
    init(_ data: [ItemType], @ViewBuilder content: @escaping (Int, ItemType) -> ContentView) {
        self.data = data
        self.content = content
    }
    
    var body: some View {
        ForEach(Array(self.data.enumerated()), id: \.offset) { idx, item in
            self.content(idx, item)
        }
    }
}

struct Pendulum: View {
    
    let height: CGFloat
    let width: CGFloat
    let radius: CGFloat
    let period: Double
    let angle: Double 
    
    @State private var a: Double = 0
    @State private var side: Bool = false
    
    var body: some View{
        ZStack{
            ZStack{
                Rectangle().frame(width: width, height: height-radius/2)
                Circle().frame(width: radius, height: radius).offset(x: 0, y: -height / 2)
                Circle().frame(width: radius/3, height: radius/3).offset(x: 0, y: -height / 2)
                Rectangle().frame(width: radius, height: radius)
                    .offset(x: 0, y: height/2)
            }.frame(width: width, height: height)
            .rotationEffect(Angle(degrees: a), anchor: .init(x: 0.5, y: 0))
            .onChange(of: side){ _ in
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + period){ side.toggle()}
                withAnimation(.easeInOut(duration: period)){ a = a==angle ? -angle : angle}
            
            }.onAppear(){ a = angle; side.toggle()}
        }.shadow(radius: 2)
    }
    
}

PlaygroundPage.current.setLiveView(Game())
