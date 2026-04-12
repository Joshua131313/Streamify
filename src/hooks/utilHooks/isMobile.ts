import { useEffect, useState } from "react";

export const useIsTouchDevice = () => {
    const [isTouch, setIsTouch] = useState(false);

    useEffect(() => {
        const mediaQuery = window.matchMedia("(hover: none) and (pointer: coarse)");

        const handleChange = () => setIsTouch(mediaQuery.matches);

        handleChange(); // initial
        mediaQuery.addEventListener("change", handleChange);

        return () => mediaQuery.removeEventListener("change", handleChange);
    }, []);

    return isTouch;
};