import { useRelatedMedia } from "../../../hooks/mediaHooks/useRelatedMedia.ts";
import type { TMediaType } from "../../../types/tmdb.ts"
import { Container } from "../../layout/Container/Container"
import { AppSwiper } from "../../ui/AppSwiper/AppSwiper.tsx";
import { MediaCard } from "../../ui/MediaCard/MediaCard";
import { SwiperSkeletonCard } from "../../ui/MediaCard/SkeletonCards/MediaSkeletonCard.tsx";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
}

export const RelatedMedia = ({ mediaId, mediaType }: Props) => {
    const { media: related, isLoading } = useRelatedMedia({ mediaId, mediaType, count: 20 });
    
    return (
        <Container title="Related media" containerId="related">
            <AppSwiper
                items={related}
                renderItem={(item) => (

                    <MediaCard media={item} />

                )}
                itemKey={(item) => String(item.id)}
                isLoading={isLoading}
                skeleton={<SwiperSkeletonCard />}
            />
        </Container>
    )
}