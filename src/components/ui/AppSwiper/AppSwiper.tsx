import { Swiper, SwiperSlide } from "swiper/react";
import { Navigation } from "swiper/modules";
import { useRef } from "react";
import { FaChevronLeft, FaChevronRight } from "react-icons/fa";
import "../../media/MediaRail/MediaRail.css"
export type TSwiperVariant = "normal" | "top10"

interface AppSwiperProps<T> {
    items: T[];
    renderItem: (item: T, index: number) => React.ReactNode;
    isLoading?: boolean;
    skeleton?: React.ReactNode;
    variant?: TSwiperVariant
}

export const AppSwiper = <T,>({
    items,
    renderItem,
    isLoading,
    skeleton,
    variant = "normal",
}: AppSwiperProps<T>) => {
    const prevRef = useRef<HTMLDivElement | null>(null);
    const nextRef = useRef<HTMLDivElement | null>(null);

    return (
        <div className="swiper-container">
            <div ref={prevRef} className="prev-button swiper-nav-button">
                <FaChevronLeft />
            </div>
            <div ref={nextRef} className="next-button swiper-nav-button">
                <FaChevronRight />
            </div>

            <Swiper
                className={`media-swiper ${variant === "top10" ? "top-10-media-swiper" : ""}`}
                slidesPerView={"auto"}
                spaceBetween={variant === "top10" ? 100 : 10}
                navigation
                modules={[Navigation]}
                onBeforeInit={(swiper) => {
                    //@ts-ignore
                    swiper.params.navigation.prevEl = prevRef.current;
                    //@ts-ignore
                    swiper.params.navigation.nextEl = nextRef.current;
                }}
            >
                {isLoading
                    ? Array.from({ length: 5 }).map((_, i) => (
                        <SwiperSlide key={i}>{skeleton}</SwiperSlide>
                    ))
                    : items.map((item, i) => (
                        <SwiperSlide key={i}>{renderItem(item, i)}</SwiperSlide>
                    ))}
            </Swiper>
        </div>
    );
};