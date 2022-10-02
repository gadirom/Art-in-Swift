import ReordableViews
import SwiftUI

struct ColorGrid: View {
    
    //@EnvironmentObject var geometryData: ContainerGeometry
    
    @Binding var colorItems: [ColorItem]
    @Binding var active: ColorItem?
    
    var itemHeight: CGFloat
    
    var onChange: (Int, Int)->()
    
    let  columns = [
        GridItem(.flexible())
    ]
    var body: some View{
        VStack{
        ReordableVGrid(items: $colorItems,
                       activeItem: $active,
                       maxItems: 5,
                       columns: columns,
                       alignment: .center,
                       spacing: 2,
                       moveAnimation: .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0),
                       selectAnimation: .spring(response: 0.1, dampingFraction: 0.7, blendDuration: 0),
                       reorderDelay: 0.3,
                       id: \.self,
                       addButton: Color.clear) { $colorItem, active, dragged, hovered, onTop, remove, select in
            ZStack{
                Rectangle()
                    .fill(colorItem.color)
                Rectangle()
                    .stroke(.white, lineWidth: 5)
                    .opacity(active ? 1 : 0)
                Rectangle()
                    .fill(.white)
                    .opacity(dragged ? 0.5 : 0)
                Rectangle()
                    .fill(.black)
                    .opacity(hovered ? 0.5 : 0)
            }.frame(height: itemHeight)
                .onTapGesture {
                    select()
                }
        } orderChanged: { from, to in
            onChange(from, to)
        }
        }
        .frame(maxHeight: .infinity)
       

    }
}
