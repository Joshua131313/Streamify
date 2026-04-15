import { useEffect, useRef } from "react";

const isIOS = () =>
    /iPhone|iPad|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

type UseEdgeSwipeProps = {
    onOpen: () => void;
    edgeSize?: number;
    minSwipeDistance?: number;
    maxVerticalDrift?: number;
};

export const useEdgeSwipe = ({
    onOpen,
    edgeSize = 30,
    minSwipeDistance = 60,
    maxVerticalDrift = 50,
}: UseEdgeSwipeProps) => {
    const startX = useRef<number | null>(null);
    const startY = useRef<number | null>(null);
    const tracking = useRef(false);

    useEffect(() => {
        const EDGE_OFFSET = isIOS() ? 20 : 0;

        const reset = () => {
            tracking.current = false;
            startX.current = null;
            startY.current = null;
        };

        const handleTouchStart = (e: TouchEvent) => {
            if (!e.touches.length) return;

            const touch = e.touches[0];
            startX.current = touch.clientX;
            startY.current = touch.clientY;

            tracking.current =
                touch.clientX > EDGE_OFFSET &&
                touch.clientX <= edgeSize + EDGE_OFFSET;
        };

        const handleTouchEnd = (e: TouchEvent) => {
            if (!tracking.current || startX.current === null || startY.current === null) return;
            if (!e.changedTouches.length) return;

            const touch = e.changedTouches[0];
            const diffX = touch.clientX - startX.current;
            const diffY = Math.abs(touch.clientY - startY.current);

            if (diffY <= maxVerticalDrift && diffX >= minSwipeDistance) {
                onOpen();
            }

            reset();
        };

        const handleMouseDown = (e: MouseEvent) => {
            startX.current = e.clientX;
            startY.current = e.clientY;

            tracking.current = e.clientX <= edgeSize;
        };

        const handleMouseUp = (e: MouseEvent) => {
            if (!tracking.current || startX.current === null || startY.current === null) return;

            const diffX = e.clientX - startX.current;
            const diffY = Math.abs(e.clientY - startY.current);

            if (diffY <= maxVerticalDrift && diffX >= minSwipeDistance) {
                onOpen();
            }

            reset();
        };

        window.addEventListener("touchstart", handleTouchStart, { passive: true });
        window.addEventListener("touchend", handleTouchEnd, { passive: true });
        window.addEventListener("touchcancel", reset, { passive: true });

        window.addEventListener("mousedown", handleMouseDown);
        window.addEventListener("mouseup", handleMouseUp);

        return () => {
            window.removeEventListener("touchstart", handleTouchStart);
            window.removeEventListener("touchend", handleTouchEnd);
            window.removeEventListener("touchcancel", reset);

            window.removeEventListener("mousedown", handleMouseDown);
            window.removeEventListener("mouseup", handleMouseUp);
        };
    }, [onOpen, edgeSize, minSwipeDistance, maxVerticalDrift]);
};