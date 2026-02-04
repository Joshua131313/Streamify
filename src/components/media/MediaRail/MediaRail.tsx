import type { TMediaRailVariant, TMediaType, TStreamCategories } from "../../../types/tmdb";
import { MediaRailProvider } from "./MediaRailContext";
import { MediaRailHeader } from "./MediaRailHeader";
import { MediaRailSwiper } from "./MediaRailSwiper";

interface Props {
    title: string;
    category: TStreamCategories;
    mediaType: TMediaType;
    variant?: TMediaRailVariant;
}

export const MediaRail = (props : Props) => {
    const { title, category, mediaType, variant = "normal" } = props

    return (
        <MediaRailProvider 
            title={title}
            category={category}
            mediaType={mediaType}
            variant={variant}
        >
            <div className="media-rail flex-col">
                <MediaRailHeader />
                <MediaRailSwiper />
            </div>
        </MediaRailProvider>
    )
}