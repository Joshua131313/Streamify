import { createContext, useContext, useEffect, useState } from "react";
import type { TLabelValue, TMediaRailVariant, TMediaType, TStreamCategories, TStreamProviders } from "../../../types/tmdb";

type MediaRailState = {
    title: string;
    category: TStreamCategories;
    variant: TMediaRailVariant;
    mediaType: TMediaType;
    setMediaType: (mediaType: TMediaType) => void;
    activeTab: TLabelValue | null;
    setActiveTab: (tab : TLabelValue) => void;
    genre?: string;
    setGenre: (genre: string) => void;
    provider?: TStreamProviders | "";
    setProvider: (provider : TStreamProviders) => void;
}

const MediaRailContext = createContext<MediaRailState | null>(null);

export const MediaRailProvider = ({
    category, 
    variant,
    mediaType, 
    title, 
    children 
} : { 
    category: TStreamCategories, 
    variant: TMediaRailVariant,
    mediaType: TMediaType, 
    title: string;
    children: React.ReactNode
}) => {
    const [activeTab, setActiveTab] = useState<TLabelValue | null>(null);
    const [type, setType] = useState<TMediaType>("movie");
    const [genre, setGenre] = useState<string>("35");
    const [provider, setProvider] = useState<TStreamProviders>("netflix")
    
    useEffect(()=> {
        setType(mediaType);
    }, [mediaType]);

    useEffect(() => {
        if(!activeTab) return;
        switch(category) {
            case "byGenre":
                setGenre(activeTab.value);
                break;
            case "provider":
                setProvider(activeTab.value as TStreamProviders);
                break;
            case "top10":
            case "trending":
            case "top_rated":
                setType(activeTab.value as TMediaType);
                break;
            default: 

        }
    }, [activeTab, category])

    return (
        <MediaRailContext.Provider 
            value={{ 
                category, 
                variant,
                title,
                mediaType: type, 
                setMediaType: setType,
                genre,
                setGenre,
                provider,
                setProvider,
                activeTab, 
                setActiveTab
            }}>
            {children}
        </MediaRailContext.Provider>
    )
}

export const useMediaRail = () => {
    const ctx = useContext(MediaRailContext);
    if(!ctx) throw new Error("useMediaRail must be used inside MediaRailProvider");
    return ctx;
}