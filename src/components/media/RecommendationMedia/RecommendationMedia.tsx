import { useRecommendedMedia } from "../../../hooks/mediaHooks/useRecommendedMedia";
import type { TMediaType } from "../../../types/tmdb.ts"
import { Container } from "../../layout/Container/Container"
import { AppSwiper } from "../../ui/AppSwiper/AppSwiper.tsx";
import { MediaCard } from "../../ui/MediaCard/MediaCard";
import { SwiperSkeletonCard } from "../../ui/MediaCard/SkeletonCards/MediaSkeletonCard.tsx";
import "./RecommendationMedia.css"

interface Props {
    mediaType: TMediaType;
    mediaId: number;
    genre: number;
}

export const RecommendationMedia = ({mediaId, mediaType, genre}: Props) => {
    const { media: recommended, isLoading } = useRecommendedMedia({mediaId, mediaType, genre, count: 20});
    const recommendedRow = recommended.map(media => {
        return (
            <MediaCard media={media} key={media.id}/>
        )
    })
    return (
        <Container title="You may like" className="media-grid" containerId="similar">
            <AppSwiper 
                items={recommended}
                renderItem={(item) => (
                    
                    <MediaCard media={item}/>
                
                )}
                itemKey={(item) => String(item.id)}
                isLoading={isLoading}
                skeleton={<SwiperSkeletonCard />}
            />
        </Container>
    )
}