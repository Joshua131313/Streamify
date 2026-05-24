import { useSearchParams } from "react-router-dom";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { PageHeader } from "../../ui/PageHeader/PageHeader";
import { GenreFilter } from "../../ui/filters/GenreFilter";
import { Container } from "../Container/Container";
import { MediaCard } from "../../ui/MediaCard/MediaCard";
import "./MediaLayout.css"
import { ContinueWatchingCard } from "../../ui/MediaCard/ContinueWatchingCard";

interface Props {
    title: string;
    subTitle: string;
    media: TMDBMedia[];
    continueWatchingCard?: boolean;
}

const MediaLibraryLayout = (props: Props) => {
    const { media, title, subTitle, continueWatchingCard } = props;
    const [searchParams] = useSearchParams();
    const urlGenre = searchParams.get("genre");

    const filteredMedia = urlGenre
        ? media.filter(m => m.genres?.some(x => x.id == Number(urlGenre)))
        : media;

    return (
        <div className="media-library-page">
            <PageHeader
                title={title}
                subTitle={subTitle}
                controls={
                    <>
                        <GenreFilter mediaType="all" includeAll />
                    </>
                }
            />
            <Container className="media-grid">
                {
                    filteredMedia.map(m => {
                        if(continueWatchingCard) {
                            return <ContinueWatchingCard media={m} key={m.id} />
                        }
                        else {
                            return <MediaCard key={m.id} media={m} />
                        }
                    })
                }
            </Container>
        </div>
    )
}
export default MediaLibraryLayout;