// MediaRailSwiper.tsx

import { useMediaRail } from "./MediaRailContext";

import { useMediaDiscover } from "../../../hooks/mediaHooks/useMediaDiscover";

import { AppSwiper } from "../../ui/AppSwiper/AppSwiper";

import { MediaCard } from "../../ui/MediaCard/MediaCard";
import { Top10MediaCard } from "../../ui/MediaCard/Top10MediaCard";

import { MediaSkeletonCard }
from "../../ui/MediaCard/SkeletonCards/MediaSkeletonCard";

import type { TSwiperVariant }
from "../../ui/AppSwiper/AppSwiper";

import type {
    TMediaTypeSelect
} from "../../../types/tmdb";

import type {
    TMediaRailQuery
} from "./MediaRail";

interface Props {
    variant: TSwiperVariant;

    buildQuery: (params: {
        mediaType: TMediaTypeSelect;
        selectedValue?: string;
    }) => TMediaRailQuery;
}

export const MediaRailSwiper = ({
    variant,
    buildQuery
}: Props) => {
    const {
        mediaType,
        selectedValue
    } = useMediaRail();

    const query = buildQuery({
        mediaType,
        selectedValue
    });

    const {
        media,
        isLoading
    } = useMediaDiscover({
        mediaType,
        category: query.category,
        genreId: query.genreId,
        provider: query.provider
    });

    return (
        <AppSwiper
            items={media}
            isLoading={isLoading}
            skeleton={<MediaSkeletonCard />}
            variant={variant}
            itemKey={(item) => String(item.id)}
            renderItem={(m, i) =>
                variant === "top10"
                    ? (
                        <Top10MediaCard
                            rank={i + 1}
                            media={m}
                        />
                    )
                    : (
                        <MediaCard media={m} />
                    )
            }
        />
    );
};