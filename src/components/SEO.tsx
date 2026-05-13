import { Helmet } from "react-helmet-async";

type SEOProps = {
    title: string;
    description?: string;
};

export const SEO = ({ title, description }: SEOProps) => {

    return (
        <Helmet title={title === "Home" ? "Streamify" : title + " | Streamify"}>
            <meta name="google-site-verification" content="4Rc6hgYHHSh5JLWl_bc6YQFKJvv7_tOzXw7MH7ogtzU" />
            {description && <meta name="description" content={description} />}
        </Helmet>
    );
};