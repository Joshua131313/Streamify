
import { Swiper, SwiperSlide } from 'swiper/react';
import { Navigation } from 'swiper/modules';
import "./MediaRail.css"
import { useMediaRail } from './MediaRailContext';
import { MediaCard } from '../../ui/MediaCard/MediaCard';
import { Top10MediaCard } from '../../ui/MediaCard/Top10MediaCard';
import { useMediaDiscover } from '../../../hooks/mediaHooks/useMediaDiscover';
import { useRef } from 'react';
import { FaChevronLeft, FaChevronRight } from 'react-icons/fa';
import { SwiperSkeletonCard } from '../../ui/MediaCard/SkeletonCards/MediaSkeletonCard';
import { AppSwiper } from '../../ui/AppSwiper/AppSwiper';

export const MediaRailSwiper = () => {
    const { genre, provider, mediaType, category, variant } = useMediaRail();
    const { media, isLoading } = useMediaDiscover({
        mediaType,
        category,
        genreId: genre,
        provider,
    })

    return (
        <AppSwiper
            items={media}
            isLoading={isLoading}
            skeleton={<SwiperSkeletonCard />}
            variant={variant}
            renderItem={(m, i) =>
                variant === "top10" ? (
                    <Top10MediaCard rank={i + 1} media={m} />
                ) : (
                    <MediaCard media={m} />
                )
            }
        />
    )
}