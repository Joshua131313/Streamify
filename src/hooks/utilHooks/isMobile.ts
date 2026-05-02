import { useEffect, useState } from "react";

export const useIsTouchDevice = () => {
    const [isTouch, setIsTouch] = useState(false);

    useEffect(() => {
        const mediaQuery = window.matchMedia("(hover: none) and (pointer: coarse)");

        const handleChange = () => {
            const isMobile = mediaQuery.matches;
            setIsTouch(isMobile);

            if (isMobile) {
                document.body.classList.add("is-mobile");
            } else {
                document.body.classList.remove("is-mobile");
            }
        };

        handleChange();

        mediaQuery.addEventListener("change", handleChange);
        return () => {
            mediaQuery.removeEventListener("change", handleChange);
            document.body.classList.remove("is-mobile"); // cleanup
        };
    }, []);

    return isTouch;
};