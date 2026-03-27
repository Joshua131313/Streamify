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
                        adjustMultiWindowSize(ref.offsetWidth, ref.offsetHeight);
                        adjustMultiWindowPosition(position.x, position.y);
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
                        adjustMultiWindowPosition(d.x, d.y);
                    }}
                    style={{ position: "fixed" }}
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