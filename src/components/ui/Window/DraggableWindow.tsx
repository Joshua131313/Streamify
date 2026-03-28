import { Rnd } from "react-rnd";
import type { WindowState } from "../../../context/WindowManagerContext";

interface Props {
    windowState: WindowState;
    size: { w: number; h: number };
    position: { x: number; y: number };
    zIndex: number;

    onResizeStop: (w: number, h: number, x: number, y: number) => void;
    onDragStop: (x: number, y: number) => void;
    onDragStart?: (e: any) => void;

    bringToFront: () => void;

    children: React.ReactNode;
}

export const DraggableWindow = ({
    windowState,
    size,
    position,
    zIndex,
    onResizeStop,
    onDragStop,
    onDragStart,
    bringToFront,
    children,
}: Props) => {
    if (windowState === "closed" || windowState === "minimized") return null;

    return (
        <Rnd
            dragHandleClassName="window-header"
            cancel=".window-controls"

            style={{ zIndex }}


            size={{
                width:
                    windowState === "fullscreen" ? window.innerWidth : size.w,
                height:
                    windowState === "fullscreen" ? window.innerHeight : size.h,
            }}

            position={{
                x: windowState === "fullscreen" ? 0 : position.x,
                y: windowState === "fullscreen" ? 0 : position.y,
            }}

            onResizeStop={(e, dir, ref, delta, pos) => {
                const viewportWidth = window.innerWidth;
                const viewportHeight = window.innerHeight;

                let width = ref.offsetWidth;
                let height = ref.offsetHeight;
                let x = pos.x;
                let y = pos.y;

                // clamp size
                if (width > viewportWidth) width = viewportWidth;
                if (height > viewportHeight) height = viewportHeight;

                // clamp position based on size
                if (x + width > viewportWidth) x = viewportWidth - width;
                if (y + height > viewportHeight) y = viewportHeight - height;

                if (x < 0) x = 0;
                if (y < 0) y = 0;

                onResizeStop(width, height, x, y);
            }}

            onDragStop={(e, d) => {
                const viewportWidth = window.innerWidth;
                const viewportHeight = window.innerHeight;

                let x = d.x;
                let y = d.y;

                // 🔥 USE SIZE AWARE CLAMP
                if (x + size.w > viewportWidth) x = viewportWidth - size.w;
                if (y + size.h > viewportHeight) y = viewportHeight - size.h;

                if (x < 0) x = 0;
                if (y < 0) y = 0;

                onDragStop(x, y);
            }}

            onDragStart={onDragStart}

            dragAxis="both"
            minWidth={250}
            minHeight={150}
        >
            {children}
        </Rnd>
    );
};