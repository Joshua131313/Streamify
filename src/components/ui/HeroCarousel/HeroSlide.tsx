import { SwiperSlide } from "swiper/react"
import type { TMDBMedia } from "../../../types/TMDBMediaType"
import { TMDBImg } from "../TMDBImg/TMDBImg";
import { PlayButton } from "../Button/PlayButton";
import { SeeMoreButton } from "../Button/SeeMoreButton";
import { FaCalendar, FaStar } from "react-icons/fa";
import { MediaMetaBadges } from "../MediaMetaBadges/MediaMetaBadges";

interface Props {
    media: TMDBMedia;
}

export const HeroSlide = (props: Props) => {
    const { media } = props

    return (
        <div className="hero-slide">
            <TMDBImg className="hero-img" path={media.backdrop_path ?? ""} alt={media.title} />
            <div className="hero-overlay"></div>
            <div className="slide-content">
                <div className="inner-slide-content">
                    <TMDBImg path={media.logo_path ?? ""} />
                    <MediaMetaBadges 
                        date={media.date}
                        genre_ids={media.genre_ids ?? []}
                        vote_average={media.vote_average}
                        genresLimit={2}
                    />
                    <div className="description">
                        {media.overview}
                    </div>
                    <div className="slide-buttons flex">
                        <PlayButton 
                            mediaType={media.mediaType}
                            mediaId={media.id} 
                        />
                        <SeeMoreButton 
                            mediaType={media.mediaType} 
                            mediaId={media.id} 
                        />
                    </div>
                </div>
            </div>
        </div>
    )
}