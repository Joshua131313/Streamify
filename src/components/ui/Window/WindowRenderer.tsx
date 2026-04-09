import { useWindowManager } from "../../../context/WindowManagerContext";
import { PlayerWindow } from "./PlayerWindow";
import { windowRegistry } from "../../../types/windowRegistry";


export const WindowRenderer = () => {
    const { windows } = useWindowManager();

    return (
        <>
            {Object.entries(windows).map(([id, windowState]) => {
                if (windowState.windowState === "closed") return null;

                const StaticComponent = windowRegistry[id];
                if (StaticComponent) {
                    return <StaticComponent key={id} />;
                }

                if (id.startsWith("?")) {
                    return <PlayerWindow key={id} id={id} />;
                }

                return null;
            })}
        </>
    );
};