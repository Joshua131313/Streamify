// components/SEO.tsx
import { Helmet } from "react-helmet-async";

type SEOProps = {
    title: string;
    description?: string;
};

export const SEO = ({ title, description }: SEOProps) => {
    console.log(title)
    return (
        <Helmet title={title === "Home" ? "Streamify" : title + " | Streamify"}>
            {description && <meta name="description" content={description} />}
        </Helmet>
    );
};