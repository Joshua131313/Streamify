import { Rnd } from "react-rnd";
import "./Sports.css";
import { FaX } from "react-icons/fa6";
import { FaCube, FaMinus, FaRegWindowMaximize, FaRegWindowRestore, FaThLarge } from "react-icons/fa";
import { BsCopy, BsSquare } from "react-icons/bs";
import { useEffect } from "react";
import { Icon } from "../../components/ui/Icon/Icon";
import { getStreamURL } from "../../utils/sports/sportsUtils";
import { useMultiWatch } from "../../context/MultiWatchContext";
import { MultiWatchContentEmpty } from "./MultiWatchContentEmpty";
import { MultiWatchContent } from "./MultiWatchContent";

export const MultiWatch = () => {
    const { multiWatch, multiWatchWindowState, removeGameFromMultiWatch, adjustMultiWatchWindow, adjustMultiWindowSize, adjustMultiWindowPosition } = useMultiWatch();

    useEffect(() => {
        if (multiWatchWindowState.windowState === "fullscreen") {
            document.body.style.overflow = "hidden";
        }
        else {
            document.body.style.overflow = "";
        }
        return () => {
            document.body.style.overflow = ""
        }
    }, [multiWatchWindowState.windowState])

    return (
        <>
            {!(multiWatchWindowState.windowState === "closed") &&
                <Rnd
                    dragHandleClassName="multi-watch-header"
                    className={`${multiWatchWindowState.windowState === "minimized" ? "minimized-window" : "multi-watch-window-parent"}`}
                    onResizeStop={(e, direction, ref, delta, position) => {
                        const SCROLLBAR_WIDTH = 15; // 🔥 your requirement

                        const viewportWidth = window.innerWidth - SCROLLBAR_WIDTH;
                        const viewportHeight = window.innerHeight;

                        let width = ref.offsetWidth;
                        let height = ref.offsetHeight;
                        let x = position.x;
                        let y = position.y;

                        // 🔥 Clamp size
                        if (width > viewportWidth) width = viewportWidth;
                        if (height > viewportHeight) height = viewportHeight;

                        // 🔥 Clamp position (keep fully visible)
                        if (x + width > viewportWidth) x = viewportWidth - width;
                        if (y + height > viewportHeight) y = viewportHeight - height;

                        // 🔥 Prevent top/left overflow
                        if (x < 0) x = 0;
                        if (y < 0) y = 0;

                        adjustMultiWindowSize(width, height);
                        adjustMultiWindowPosition(x, y);
                    }}
                    onDragStart={(e: any) => {
                        if (multiWatchWindowState.windowState === "fullscreen") {
                            const mouseX = e.clientX;
                            const mouseY = e.clientY;

                            const width = multiWatchWindowState.lastWindowOpenedSize.w;

                            adjustMultiWatchWindow("opened");

                            adjustMultiWindowPosition(
                                mouseX - width / 2,
                                mouseY - 20
                            );
                        }
                    }}
                    onDragStop={(e, d) => {
                        const clampedY = Math.max(0, d.y); // 🔥 prevents going above top
                        const clampedX = Math.max(0, d.x); // optional (prevents left overflow)

                        adjustMultiWindowPosition(clampedX, clampedY);
                    }}

                    size={{
                        width:
                            multiWatchWindowState.windowState === "fullscreen"
                                ? window.innerWidth
                                : multiWatchWindowState.lastWindowOpenedSize.w,

                        height:
                            multiWatchWindowState.windowState === "fullscreen"
                                ? window.innerHeight
                                : multiWatchWindowState.lastWindowOpenedSize.h,
                    }}

                    position={{
                        x:
                            multiWatchWindowState.windowState === "fullscreen"
                                ? 0
                                : multiWatchWindowState.lastWindowOpenedPosition.x,

                        y:
                            multiWatchWindowState.windowState === "fullscreen"
                                ? 0
                                : multiWatchWindowState.lastWindowOpenedPosition.y,
                    }}
                >
                    <div className="multi-watch-window">
                        <div className="multi-watch-header">
                            <span>Multi Watch</span>
                            <div className="multi-watch-header-controls">
                                <div onClick={() => adjustMultiWatchWindow("minimized")}>
                                    <FaMinus />
                                </div>
                                <div onClick={() => adjustMultiWatchWindow(multiWatchWindowState.windowState === "fullscreen" ? "opened" : "fullscreen")}>
                                    {multiWatchWindowState.windowState === "fullscreen" ?
                                        <FaRegWindowRestore />
                                        :
                                        <BsSquare />
                                    }
                                </div>
                                <div className="multi-watch-close-control" onClick={() => adjustMultiWatchWindow("closed")}>
                                    <FaX />
                                </div>
                            </div>
                        </div>
                        <div className="multi-watch-content">
                            {multiWatch.length === 0 ? (
                                <MultiWatchContentEmpty />
                            ) : (
                                <MultiWatchContent />
                            )}
                        </div>
                    </div>
                </Rnd>
            }
            {
                multiWatchWindowState.windowState === "minimized" &&
                <Icon
                    Icon={FaThLarge}
                    className="multi-watch-icon"
                    onClick={() => adjustMultiWatchWindow(multiWatchWindowState.lastWindowState)} // set the window state to last state
                />
            }
        </>
    );
};