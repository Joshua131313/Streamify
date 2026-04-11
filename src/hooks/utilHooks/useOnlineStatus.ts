import { useEffect, useState } from "react";

export const useOnlineStatus = () => {
    const [isOnline, setIsOnline] = useState(true);

    useEffect(() => {
        let interval: any;

        const checkConnection = async () => {
            if (!navigator.onLine) {
                setIsOnline(false);
                return;
            }

            try {
                const res = await fetch("/api/health", {
                    method: "HEAD",
                    cache: "no-store",
                });

                setIsOnline(res.ok);
            } catch {
                setIsOnline(false);
            }
        };

        checkConnection();

        interval = setInterval(checkConnection, 3000);

        const handleOnline = () => checkConnection();
        const handleOffline = () => setIsOnline(false);

        window.addEventListener("online", handleOnline);
        window.addEventListener("offline", handleOffline);

        return () => {
            clearInterval(interval);
            window.removeEventListener("online", handleOnline);
            window.removeEventListener("offline", handleOffline);
        };
    }, []);

    return isOnline;
};