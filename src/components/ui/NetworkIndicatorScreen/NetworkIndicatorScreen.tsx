import { FaWifi } from "react-icons/fa";
import { useEffect, useRef, useState } from "react";
import { useOnlineStatus } from "../../../hooks/utilHooks/useOnlineStatus";
import "./NetworkIndicatorScreen.css";

export const NetworkIndicatorScreen = () => {
    const isOnline = useOnlineStatus();

    const [showOnline, setShowOnline] = useState(false);
    const prevIsOnline = useRef(isOnline); 

    useEffect(() => {
        if (isOnline && !prevIsOnline.current) {
            setShowOnline(true);

            const timeout = setTimeout(() => {
                setShowOnline(false);
            }, 1000);

            return () => clearTimeout(timeout);
        }

        prevIsOnline.current = isOnline;
    }, [isOnline]);

    if (!isOnline) {
        return (
            <div className="offline-container offline">
                <FaWifi />
                <span>You are offline, try reconnecting to the internet...</span>
            </div>
        );
    }

    if (showOnline) {
        return (
            <div className="offline-container online">
                <FaWifi />
                <span>Back online</span>
            </div>
        );
    }

    return null;
};