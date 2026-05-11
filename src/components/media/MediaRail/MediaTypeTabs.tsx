// MediaTypeTabs.tsx

import { useLayoutEffect, useRef, useState } from "react";

import type { TLabelValue } from "../../../types/tmdb";

import { useMediaRail } from "./MediaRailContext";

const tabs: TLabelValue[] = [
    {
        label: "Movies",
        value: "movie"
    },
    {
        label: "Series",
        value: "tv"
    }
];

export const MediaTypeTabs = () => {
    const {
        mediaType,
        setMediaType
    } = useMediaRail();

    const containerRef =
        useRef<HTMLDivElement | null>(null);

    const tabRefs =
        useRef<(HTMLDivElement | null)[]>([]);

    const [indicator, setIndicator] = useState({
        left: 0,
        width: 0
    });

    const updateIndicator = () => {
        const container = containerRef.current;

        const index =
            tabs.findIndex(
                t => t.value === mediaType
            );

        const activeEl =
            tabRefs.current[index];

        if (!container || !activeEl) return;

        const cRect =
            container.getBoundingClientRect();

        const aRect =
            activeEl.getBoundingClientRect();

        setIndicator({
            left: aRect.left - cRect.left,
            width: aRect.width
        });
    };

    useLayoutEffect(() => {
        updateIndicator();
    }, [mediaType]);

    return (
        <div
            className="rail-tabs flex-row"
        ref={containerRef}
        >
            <div
                className="tab-indicator"
                style={{
                    width: `${indicator.width}px`,
                    transform: `translateX(${indicator.left}px)`
                }}
            />

            {
                tabs.map((tab, i) => (
                    <div
                        key={tab.value}
                        ref={(el) => {
                            tabRefs.current[i] = el;
                        }}
                        className={`tab ${
                            mediaType === tab.value
                                ? "active-tab"
                                : ""
                        }`}
                        onClick={() => {
                            setMediaType(
                                tab.value as "movie" | "tv"
                            );
                        }}
                    >
                        {tab.label}
                    </div>
                ))
            }
        </div>
    );
};