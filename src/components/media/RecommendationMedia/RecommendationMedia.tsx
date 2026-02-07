import { useRecommendedMedia } from "../../../hooks/mediaHooks/useRecommendedMedia";
import type { TMediaType } from "../../../types/tmdb.ts"
import { Container } from "../../layout/Container/Container"
import { MediaCard } from "../../ui/MediaCard/MediaCard";
import "./RecommendationMedia.css"

interface Props {
    mediaType: TMediaType;
    mediaId: number;
}

export const RecommendationMedia = ({mediaId, mediaType}: Props) => {
    const { media: recommended } = useRecommendedMedia({mediaId, mediaType, count: 15});
    const recommendedRow = recommended.map(media => {
        return (
            <MediaCard media={media}/>
        )
    })

    return (
        <Container title="You may like" className="media-grid" containerId="similar">
            {recommendedRow}
        </Container>
    )
}