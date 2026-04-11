import { useEffect, useState } from "react";

export const useOnlineStatus = () => {
    const [isOnline, setIsOnline] = useState(true);

    useEffect(() => {
        const checkConnection = async () => {
            try {
                // lightweight request (can be your API too)
                await fetch("/logo/streamify-logo.ico", { cache: "no-store" });
                setIsOnline(true);
            } catch {
                setIsOnline(false);
            }
                    console.log(isOnline)

        };
        checkConnection(); // initial check

        const interval = setInterval(checkConnection, 3000);

        return () => clearInterval(interval);
    }, []);

    return isOnline;
};