// MediaRailContext.tsx

import {
    createContext,
    useContext,
    useState
} from "react";

import type { TMediaTypeSelect } from "../../../types/tmdb";

type MediaRailState = {
    mediaType: TMediaTypeSelect;
    setMediaType: (mediaType: TMediaTypeSelect) => void;

    selectedValue?: string;
    setSelectedValue: (value: string) => void;
};

const MediaRailContext = createContext<MediaRailState | null>(null);

export const MediaRailProvider = ({
    children,
    defaultSelect
}: {
    children: React.ReactNode;
    defaultSelect?: string;
}) => {
    const [mediaType, setMediaType] =
        useState<TMediaTypeSelect>("movie");

    const [selectedValue, setSelectedValue] =
        useState(defaultSelect);

    return (
        <MediaRailContext.Provider
            value={{
                mediaType,
                setMediaType,

                selectedValue,
                setSelectedValue
            }}
        >
            {children}
        </MediaRailContext.Provider>
    );
};

export const useMediaRail = () => {
    const ctx = useContext(MediaRailContext);

    if (!ctx) {
        throw new Error(
            "useMediaRail must be used inside MediaRailProvider"
        );
    }

    return ctx;
};