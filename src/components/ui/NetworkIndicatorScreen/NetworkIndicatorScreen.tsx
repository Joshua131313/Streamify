import { FaWifi } from "react-icons/fa";
import { useEffect, useState } from "react";
import { useOnlineStatus } from "../../../hooks/utilHooks/useOnlineStatus";
import "./NetworkIndicatorScreen.css"

export const NetworkIndicatorScreen = () => {
    const isOnline = useOnlineStatus();

    const [wasOffline, setWasOffline] = useState(false);
    const [showOnline, setShowOnline] = useState(false);

    useEffect(() => {
        if (!isOnline) {
            setWasOffline(true);
        }

        if (isOnline && wasOffline) {
            // just came back online
            setShowOnline(true);
            setWasOffline(false);

            const timeout = setTimeout(() => {
                setShowOnline(false);
            }, 1000); // show for 1 second

            return () => clearTimeout(timeout);
        }
    }, [isOnline, wasOffline]);

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