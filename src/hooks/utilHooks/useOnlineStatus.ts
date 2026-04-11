import { useEffect, useState } from "react";

export const useOnlineStatus = () => {
    const [isOnline, setIsOnline] = useState(navigator.onLine);

    useEffect(() => {
        const updateStatus = () => {
            console.log("checking:", navigator.onLine);
            setIsOnline(navigator.onLine);
        };

        // event listeners (may not fire reliably)
        window.addEventListener("online", updateStatus);
        window.addEventListener("offline", updateStatus);

        // fallback polling (THIS fixes your issue)
        const interval = setInterval(updateStatus, 2000);

        return () => {
            window.removeEventListener("online", updateStatus);
            window.removeEventListener("offline", updateStatus);
            clearInterval(interval);
        };
    }, [navigator]);

    return isOnline;
};