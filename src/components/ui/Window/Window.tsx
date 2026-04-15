import { Rnd } from "react-rnd";
import { FaMinus, FaRegWindowRestore } from "react-icons/fa";
import { FaX } from "react-icons/fa6";
import { BsSquare } from "react-icons/bs";

import "./Window.css";
import { useWindow } from "../../../hooks/utilHooks/useWindow";
import { useEffect, useLayoutEffect, useRef } from "react";

interface Props {
    id: string;
    title: string;
    children: React.ReactNode;
    minimizedIcon: React.ReactNode;
    className?: string;
}

export const Window = ({ id, title, children, minimizedIcon, className }: Props) => {
    const {
        appWindow,
        close,
        minimize,
        toggleFullscreen,
        toggleWindow,
        setSize,
        setPosition,
        open,
        getWindowIndex
    } = useWindow(id);
    
    const rndRef = useRef<Rnd | null>(null);
    
    if (!appWindow) return null;

    const WindowMinimizedIcon = () => {
        return (
            <div
                style={{
                    bottom: 55 * (getWindowIndex()) + 20
                }}
                className={`window-minimized-icon ${appWindow.windowState === "minimized" ? " active" : ""}`}
                onClick={toggleWindow}
            >
                {minimizedIcon}
            </div>
        );
    }

    if (appWindow.windowState === "closed") return null;

    const bringToFront = () => {
        if (!window.__zCounter) {
            window.__zCounter = 1000;
        }

        window.__zCounter += 1;

        const el = rndRef.current?.resizableElement?.current;

        if (el) {
            el.style.zIndex = String(window.__zCounter);
        }
    };

    return (
        <>
            <Rnd
                key={`${id}`}
                ref={rndRef}
                dragHandleClassName="window-header"
                cancel=".window-controls"
                style={{ zIndex: appWindow.zIndex}}
                className={`${className} ${appWindow.windowState === "minimized" ? "window-minimized" : ""}`}
                size={{
                    width:
                        appWindow.windowState === "fullscreen"
                            ? window.innerWidth
                            : appWindow.size.w,
                    height:
                        appWindow.windowState === "fullscreen"
                            ? window.innerHeight
                            : appWindow.size.h,
                }}

                position={{
                    x: appWindow.windowState === "fullscreen" ? window.scrollX : appWindow.position.x,
                    y: appWindow.windowState === "fullscreen" ? window.scrollY : appWindow.position.y,
                }}

                onResizeStop={(e, dir, ref, delta, pos) => {
                    const SCROLLBAR_WIDTH = 15;

                    const viewportWidth = window.innerWidth - SCROLLBAR_WIDTH;
                    const viewportHeight = window.innerHeight;

                    let width = ref.offsetWidth;
                    let height = ref.offsetHeight;
                    let x = pos.x;
                    let y = pos.y;

                    if (width > viewportWidth) width = viewportWidth;
                    if (height > viewportHeight) height = viewportHeight;

                    if (x + width > viewportWidth) x = viewportWidth - width;
                    if (y + height > viewportHeight) y = viewportHeight - height;

                    if (x < 0) x = 0;
                    if (y < 0) y = 0;

                    setSize(width, height);
                    setPosition(x, y);
                }}

                onDragStop={(e, d) => {
                    document.body.classList.remove("dragging");

                    const clampedX = Math.max(0, d.x);
                    const clampedY = Math.max(0, d.y);

                    setPosition(clampedX, clampedY);
                }}

                // ✅ FULLSCREEN DRAG EXIT (same as old)
                onDragStart={(e: any) => {
                    document.body.classList.add("dragging");
                    if (appWindow.windowState === "fullscreen") {
                        const mouseX = e.clientX;
                        const mouseY = e.clientY;

                        const width = appWindow.size.w;

                        open();

                        setPosition(mouseX - width / 2, mouseY - 20);
                    }
                }}
                onMouseDown={bringToFront}
                dragAxis="both"
                minWidth={250}
                minHeight={150}
            >
                <div className="window-shell">
                    {/* HEADER */}
                    <div className="window-header">
                        <span>{title}</span>

                        <div className="window-controls">
                            <div
                                onClick={(e) => {
                                    e.stopPropagation();
                                    minimize();
                                }}
                            >
                                <FaMinus />
                            </div>

                            <div
                                onClick={(e) => {
                                    e.stopPropagation();
                                    toggleFullscreen();
                                    bringToFront();
                                }}
                            >
                                {appWindow.windowState === "fullscreen" ? (
                                    <FaRegWindowRestore />
                                ) : (
                                    <BsSquare />
                                )}
                            </div>

                            <div
                                className="window-close"
                                onClick={(e) => {
                                    e.stopPropagation();
                                    close();
                                }}
                            >
                                <FaX />
                            </div>
                        </div>
                    </div>
                    <div className="window-content">{children}</div>
                </div>
            </Rnd>
            <WindowMinimizedIcon />
        </>
    );
};