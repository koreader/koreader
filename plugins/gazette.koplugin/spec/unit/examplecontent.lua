local ExampleContent = {

}

ExampleContent.XHTML_EXAMPLE_CONTENT = [[
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">
<head>
<title>Minimal EPUB 3.2</title>
<link rel="stylesheet" href="css/style.css"/>
<link href="https://fonts.googleapis.com/css?family=Charmonman" rel="stylesheet"/>
</head>
<body>
<!-- uses WOFF2 font
     uses remote font
     uses non-SSV epub type attribute value
     includes foreign resource without fallback
     -->
<section epub:type="foo">
<p class="remote">This text should be in Charoman</p>
<p class="woff2">This text should be in Open Sans.</p>
</section>
</body>
</html>
]]

ExampleContent.IMAGE_ELEMENT_TESTS = [[
<img src="/ourworldindata.org/oms-logo.svg" alt="Oxford Martin School logo"/>
<img src="http://ourworldindata.org/gcdl-logo.svg" alt="Global Change Data Lab logo"/>
<img src="https://ourworldindata.org/exports/number-of-reported-guinea-worm-dracunculiasis-cases-d1fed9422fc3dafb4da18d4e40f43039_v24_850x600.svg" width="850" height="600" loading="lazy" data-no-lightbox="" alt="Number of reported guinea worm dracunculiasis cases d1fed9422fc3dafb4da18d4e40f43039 v24 850x600">
<img src="https://ourworldindata.org/exports/number-of-reported-guinea-worm-dracunculiasis-cases-363f79b8507585925757acc3e980a6c4_v24_850x600.svg" width="850" height="600" loading="lazy" data-no-lightbox="" alt="Number of reported guinea worm dracunculiasis cases 363f79b8507585925757acc3e980a6c4 v24 850x600">
<img src="https://ourworldindata.org/exports/progress-towards-guinea-worm-disease-eradication_v11_850x600.svg" width="850" height="600" loading="lazy" data-no-lightbox="" alt="Progress towards guinea worm disease eradication v11 850x600">
<img src="https://ourworldindata.org/grapher/exports/year-country-was-certified-free-of-guinea-worm-disease.svg" alt="Year country was certified free of guinea worm disease" loading="lazy">
<img src="https://ourworldindata.org/uploads/2021/06/Clean-Water-thumbnail-150x79.png" data-high-res-src="https://ourworldindata.org/uploads/2021/06/Clean-Water-thumbnail.png" alt="Clean water thumbnail" loading="lazy">
<img src="https://ourworldindata.org/uploads/2022/04/Polio-featured-image-150x59.png" data-high-res-src="https://ourworldindata.org/uploads/2022/04/Polio-featured-image.png" alt="Polio featured image" loading="lazy">
<img src="https://ourworldindata.org/oms-logo.svg" alt="Oxford Martin School logo" loading="lazy"/>
<img src="https://ourworldindata.org/yc-logo.png" alt="Y Combinator logo" loading="lazy"/>
<img src="https://ourworldindata.org/gcdl-logo.svg" alt="Global Change Data Lab logo" loading="lazy"/>
]]

ExampleContent.HTML_EXAMPLE_WITH_IMAGES = [[
<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"/><title>Guinea worm disease is close to being eradicated – how was this progress achieved? - Our World in Data</title><meta name="description" content="In the late 1980s, there were near a million new cases of guinea worm disease recorded worldwide. In 2021, there were only 15. How was this achieved?"/><link rel="canonical" href="https://ourworldindata.org/guinea-worm-path-eradication"/><link rel="alternate" type="application/atom+xml" href="/atom.xml"/><link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png"/><meta property="fb:app_id" content="1149943818390250"/><meta property="og:url" content="https://ourworldindata.org/guinea-worm-path-eradication"/><meta property="og:title" content="Guinea worm disease is close to being eradicated – how was this progress achieved?"/><meta property="og:description" content="In the late 1980s, there were near a million new cases of guinea worm disease recorded worldwide. In 2021, there were only 15. How was this achieved?"/><meta property="og:image" content="https://ourworldindata.org/app/uploads/2018/10/Guinea-worm-eradication-thumbnail-768x381.png"/><meta property="og:site_name" content="Our World in Data"/><meta name="twitter:card" content="summary_large_image"/><meta name="twitter:site" content="@OurWorldInData"/><meta name="twitter:creator" content="@OurWorldInData"/><meta name="twitter:title" content="Guinea worm disease is close to being eradicated – how was this progress achieved?"/><meta name="twitter:description" content="In the late 1980s, there were near a million new cases of guinea worm disease recorded worldwide. In 2021, there were only 15. How was this achieved?"/><meta name="twitter:image" content="https://ourworldindata.org/app/uploads/2018/10/Guinea-worm-eradication-thumbnail-768x381.png"/><link href="https://fonts.googleapis.com/css?family=Lato:300,400,400i,700,700i|Playfair+Display:400,700&amp;display=swap" rel="stylesheet"/><link rel="stylesheet" href="https://ourworldindata.org/assets/commons.css"/><link rel="stylesheet" href="https://ourworldindata.org/assets/owid.css"/><!-- Google Tag Manager -->
<script>(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],
j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=
'https://www.googletagmanager.com/gtm.js?id='+i+dl;f.parentNode.insertBefore(j,f);
})(window,document,'script','dataLayer','GTM-N2D4V8S');</script>
<!-- End Google Tag Manager --></head><body class=""><header class="site-header"><div class="wrapper site-navigation-bar"><div class="site-logo"><a href="/">Our World<br/> in Data</a></div><nav class="site-navigation"><div class="topics-button-wrapper"><a href="/#entries" class="topics-button"><div class="label">Articles <br/><strong>by topic</strong></div><div class="icon"><svg width="12" height="6"><path d="M0,0 L12,0 L6,6 Z" fill="currentColor"></path></svg></div></a></div><div><div class="site-primary-navigation"><form class="HeaderSearch" action="/search" method="GET"><input type="search" name="q" placeholder="Search..."/><div class="icon"><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="magnifying-glass" class="svg-inline--fa fa-magnifying-glass " role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="currentColor" d="M500.3 443.7l-119.7-119.7c27.22-40.41 40.65-90.9 33.46-144.7C401.8 87.79 326.8 13.32 235.2 1.723C99.01-15.51-15.51 99.01 1.724 235.2c11.6 91.64 86.08 166.7 177.6 178.9c53.8 7.189 104.3-6.236 144.7-33.46l119.7 119.7c15.62 15.62 40.95 15.62 56.57 0C515.9 484.7 515.9 459.3 500.3 443.7zM79.1 208c0-70.58 57.42-128 128-128s128 57.42 128 128c0 70.58-57.42 128-128 128S79.1 278.6 79.1 208z"></path></svg></div></form><ul class="site-primary-links"><li><a href="/blog" data-track-note="header-navigation">Latest</a></li><li><a href="/about" data-track-note="header-navigation">About</a></li><li><a href="/donate" data-track-note="header-navigation">Donate</a></li></ul></div><div class="site-secondary-navigation"><ul class="site-secondary-links"><li><a href="/charts" data-track-note="header-navigation">All charts</a></li><li><a href="https://sdg-tracker.org" data-track-note="header-navigation">Sustainable Development Goals Tracker</a></li></ul></div></div></nav><div class="header-logos-wrapper"><a href="https://www.oxfordmartin.ox.ac.uk/global-development" class="oxford-logo"><img src="https://ourworldindata.org/oms-logo.svg" alt="Oxford Martin School logo"/></a><a href="https://global-change-data-lab.org/" class="gcdl-logo"><img src="https://ourworldindata.org/gcdl-logo.svg" alt="Global Change Data Lab logo"/></a></div><div class="mobile-site-navigation"><button data-track-note="mobile-search-button"><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="magnifying-glass" class="svg-inline--fa fa-magnifying-glass " role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="currentColor" d="M500.3 443.7l-119.7-119.7c27.22-40.41 40.65-90.9 33.46-144.7C401.8 87.79 326.8 13.32 235.2 1.723C99.01-15.51-15.51 99.01 1.724 235.2c11.6 91.64 86.08 166.7 177.6 178.9c53.8 7.189 104.3-6.236 144.7-33.46l119.7 119.7c15.62 15.62 40.95 15.62 56.57 0C515.9 484.7 515.9 459.3 500.3 443.7zM79.1 208c0-70.58 57.42-128 128-128s128 57.42 128 128c0 70.58-57.42 128-128 128S79.1 278.6 79.1 208z"></path></svg></button><button data-track-note="mobile-newsletter-button"><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="envelope-open-text" class="svg-inline--fa fa-envelope-open-text " role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="currentColor" d="M256 417.1c-16.38 0-32.88-4.1-46.88-15.12L0 250.9v213.1C0 490.5 21.5 512 48 512h416c26.5 0 48-21.5 48-47.1V250.9l-209.1 151.1C288.9 412 272.4 417.1 256 417.1zM493.6 163C484.8 156 476.4 149.5 464 140.1v-44.12c0-26.5-21.5-48-48-48l-77.5 .0016c-3.125-2.25-5.875-4.25-9.125-6.5C312.6 29.13 279.3-.3732 256 .0018C232.8-.3732 199.4 29.13 182.6 41.5c-3.25 2.25-6 4.25-9.125 6.5L96 48c-26.5 0-48 21.5-48 48v44.12C35.63 149.5 27.25 156 18.38 163C6.75 172 0 186 0 200.8v10.62l96 69.37V96h320v184.7l96-69.37V200.8C512 186 505.3 172 493.6 163zM176 255.1h160c8.836 0 16-7.164 16-15.1c0-8.838-7.164-16-16-16h-160c-8.836 0-16 7.162-16 16C160 248.8 167.2 255.1 176 255.1zM176 191.1h160c8.836 0 16-7.164 16-16c0-8.838-7.164-15.1-16-15.1h-160c-8.836 0-16 7.162-16 15.1C160 184.8 167.2 191.1 176 191.1z"></path></svg></button><button data-track-note="mobile-hamburger-button"><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="bars" class="svg-inline--fa fa-bars " role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><path fill="currentColor" d="M0 96C0 78.33 14.33 64 32 64H416C433.7 64 448 78.33 448 96C448 113.7 433.7 128 416 128H32C14.33 128 0 113.7 0 96zM0 256C0 238.3 14.33 224 32 224H416C433.7 224 448 238.3 448 256C448 273.7 433.7 288 416 288H32C14.33 288 0 273.7 0 256zM416 448H32C14.33 448 0 433.7 0 416C0 398.3 14.33 384 32 384H416C433.7 384 448 398.3 448 416C448 433.7 433.7 448 416 448z"></path></svg></button></div></div></header><div class="alert-banner"><div class="content"><div class="text"><strong>COVID-19 vaccinations, cases, excess mortality, and much more</strong></div><a href="/coronavirus#explore-the-global-situation" data-track-note="covid-banner-click">Explore our COVID-19 data</a></div></div><main><article class="page no-sidebar thin-banner"><div class="offset-header"><header class="article-header"><div class="article-titles"><h1 class="entry-title">Guinea worm disease is close to being eradicated – how was this progress achieved?</h1></div></header></div><div class="content-wrapper"><div class="offset-content"><div class="content-and-footnotes"><div class="article-content"><section><div class="wp-block-columns is-style-sticky-right"><div class="wp-block-column"><div class="article-meta"><div class="excerpt">In the late 1980s, there were near a million new cases of guinea worm disease recorded worldwide. In 2021, there were only 15. How was this achieved?</div><div class="authors-byline"><a href="/team">by Saloni Dattani and Fiona Spooner</a></div><div class="published-updated"><time>July 07, 2022</time></div></div></div><div class="wp-block-column"></div></div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<p>Guinea worm disease is a painful and debilitating disease that used to be common in Asia, the Middle East, and many countries in Africa.&nbsp;</p>



<p>It’s now close to being eradicated worldwide. This success is thanks to an eradication program that has focused on water treatment and filtration, public education, and providing safe sources of drinking water to reduce its spread.</p>



<h4 id="what-is-guinea-worm-disease">What is guinea worm disease?<a class="deep-link" href="#what-is-guinea-worm-disease"></a></h4>
</div>



<div class="wp-block-column"></div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<p>The disease is caused by a parasite called guinea worm (<em>Dracunculiasis medinensis</em>). The worm’s larvae are carried by water fleas found in stagnant water in ponds, open wells, and freshwater lakes.</p>



<p>When someone drinks contaminated water, the larvae can invade their stomach and intestines.&nbsp;</p>



<p>Over time, they mature into adult worms – with female worms growing up to around a meter in length – and crawl through people’s connective tissue, joints, and bones. This growth leads to arthritic conditions, which can debilitate people for months. Around one in two hundred infected people develop a permanent disability from the disease.<a id="ref-1" class="ref" href="#note-1"><sup>1</sup></a></p>



<p>Around a year after the infection, the worm begins to emerge from the skin through a painful blister. This process also increases the risks of other infections.</p>



<p>People often try to find relief from the infection by putting their blisters in open water. This might bring some temporary relief for them, but makes it harder to eliminate the disease. In the water, the worm can release its own larvae and if the water contains water fleas, this restarts the life cycle of the guinea worm.&nbsp;</p>



<p>The disease can be treated with pain medication and antibiotics, and by carefully removing the worm when it emerges.<a id="ref-2" class="ref" href="#note-2"><sup>2</sup></a></p>
</div>



<div class="wp-block-column"></div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<h4 id="guinea-worm-disease-used-to-be-common">Guinea worm disease used to be common<a class="deep-link" href="#guinea-worm-disease-used-to-be-common"></a></h4>
</div>



<div class="wp-block-column"></div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<p>This parasite has troubled humans for a long time. There are records of guinea worm disease dating back thousands of years.<a id="ref-3" class="ref" href="#note-3"><sup>3</sup></a></p>



<p>It was endemic in Asia, the Middle East, and many countries in Africa in the early twentieth century.<a id="ref-4" class="ref" href="#note-4"><sup>4</sup></a></p>



<p>It was common in poor remote villages without <a href="https://ourworldindata.org/water-access">access to clean drinking water</a>. This was because sources of stagnant water – such as large open wells and ponds – could be contaminated by water fleas that contained guinea worm larvae.</p>



<p>Unfortunately, people do not develop immunity to the disease if they have been infected, which means it was common for people to be reinfected several times. For example, in the 1960s, in some villages in South India, more than 70% of adults infected once had been reinfected later on, and 10% had been infected at least 10 times.<a id="ref-5" class="ref" href="#note-5"><sup>5</sup></a></p>



<p>By the 1980s, guinea worm disease was known to be endemic in 20 countries in South Asia and parts of Africa. We see this in the map, which shows the number of reported cases by country in 1989.</p>



<p>In 1986, around 35,000 cases were reported to the World Health Organization (WHO). As surveillance improved, the number of detected cases increased to 890,000 in 1989.</p>
</div>



<div class="wp-block-column">

                <figure data-grapher-src="https://ourworldindata.org/grapher/number-of-reported-guinea-worm-dracunculiasis-cases?tab=map&amp;time=1989" class="grapherPreview">
                    <a href="https://ourworldindata.org/grapher/number-of-reported-guinea-worm-dracunculiasis-cases?tab=map&amp;time=1989" target="_blank">
                        <div><img src="https://ourworldindata.org/exports/number-of-reported-guinea-worm-dracunculiasis-cases-d1fed9422fc3dafb4da18d4e40f43039_v24_850x600.svg" width="850" height="600" loading="lazy" data-no-lightbox="" alt="Number of reported guinea worm dracunculiasis cases d1fed9422fc3dafb4da18d4e40f43039 v24 850x600"></div>
                        <div class="interactionNotice">
                            <span class="icon"><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="hand-pointer" class="svg-inline--fa fa-hand-pointer fa-w-14" role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 617">
    <path fill="currentColor" d="M448,344.59v96a40.36,40.36,0,0,1-1.06,9.16l-32,136A40,40,0,0,1,376,616.59H168a40,40,0,0,1-32.35-16.47l-128-176a40,40,0,0,1,64.7-47.06L104,420.58v-276a40,40,0,0,1,80,0v200h8v-40a40,40,0,1,1,80,0v40h8v-24a40,40,0,1,1,80,0v24h8a40,40,0,1,1,80,0Zm-256,80h-8v96h8Zm88,0h-8v96h8Zm88,0h-8v96h8Z" transform="translate(0 -0.41)"></path>
    <path fill="currentColor" opacity="0.6" d="M239.76,234.78A27.5,27.5,0,0,1,217,192a87.76,87.76,0,1,0-145.9,0A27.5,27.5,0,1,1,25.37,222.6,142.17,142.17,0,0,1,1.24,143.17C1.24,64.45,65.28.41,144,.41s142.76,64,142.76,142.76a142.17,142.17,0,0,1-24.13,79.43A27.47,27.47,0,0,1,239.76,234.78Z" transform="translate(0 -0.41)"></path>
</svg></span>
                            <span class="label">Click to open interactive version</span>
                        </div>
                    </a>
                </figure>
</div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<h4 id="how-can-guinea-worm-disease-be-prevented">How can guinea worm disease be prevented?<a class="deep-link" href="#how-can-guinea-worm-disease-be-prevented"></a></h4>
</div>



<div class="wp-block-column"></div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<p>Unfortunately, there are no vaccines against guinea worm disease.&nbsp;</p>



<p>However, the disease has several features that make it easy to prevent.&nbsp;</p>



<p>First, humans are the main ‘host’ of the disease, with only a few exceptions.<a id="ref-6" class="ref" href="#note-6"><sup>6</sup></a> The worm larvae are unable to survive for more than a few weeks in water fleas.<a id="ref-7" class="ref" href="#note-7"><sup>7</sup></a> This means the worms can easily die out if they are prevented from infecting humans.</p>



<p>That brings us to our second point: we know how to stop it from infecting people. When people avoid drinking contaminated water that contains water fleas and guinea worm larvae, they are prevented from being infected.</p>



<p>Third, the disease is seasonal. People infected in one season tend to release worms a year later, which restarts the seasonal cycle. In the past, when villages halted the spread of worms in a single season, the disease stopped entirely unless it was reintroduced from somewhere else.<a id="ref-8" class="ref" href="#note-8"><sup>8</sup></a></p>
</div>



<div class="wp-block-column"></div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<h4 id="the-world-has-made-huge-progress-against-the-disease">The world has made huge progress against the disease<a class="deep-link" href="#the-world-has-made-huge-progress-against-the-disease"></a></h4>
</div>



<div class="wp-block-column"></div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<p>The world has made tremendous progress in reducing the burden of this disease with the knowledge of how to prevent it from spreading.</p>



<p>The campaign to eradicate guinea worm disease began in the 1980s. It was led by a number of organizations including the Centers for Disease Control and Prevention in the United States (US CDC), the Carter Center, the WHO, and the United Nations Children’s Fund (UNICEF).<a id="ref-9" class="ref" href="#note-9"><sup>9</sup></a></p>



<p>Village volunteers have played a major role in the eradication program. They provide people with water filters and larvicides, educate them about where to drink clean water, record cases, help treat patients who are suffering from the disease, and prevent them from releasing worms into the water.<a id="ref-10" class="ref" href="#note-10"><sup>10</sup></a></p>



<p>Another key driver of progress is access to improved drinking water sources, which has become more common in many countries.</p>



<p>You can see the change since the start of the eradication campaign in the chart. Cases of guinea worm disease declined rapidly across many countries.&nbsp;</p>



<p>Over 890,000 cases were recorded worldwide in 1989. By 2021, there were just 15.&nbsp;</p>



<p>Almost all of the 15 cases were recorded in Chad.</p>
</div>



<div class="wp-block-column">

                <figure data-grapher-src="https://ourworldindata.org/grapher/number-of-reported-guinea-worm-dracunculiasis-cases?tab=chart&amp;country=OWID_WRL~UGA~TCD~PAK~IND~MRT" class="grapherPreview">
                    <a href="https://ourworldindata.org/grapher/number-of-reported-guinea-worm-dracunculiasis-cases?tab=chart&amp;country=OWID_WRL~UGA~TCD~PAK~IND~MRT" target="_blank">
                        <div><img src="https://ourworldindata.org/exports/number-of-reported-guinea-worm-dracunculiasis-cases-363f79b8507585925757acc3e980a6c4_v24_850x600.svg" width="850" height="600" loading="lazy" data-no-lightbox="" alt="Number of reported guinea worm dracunculiasis cases 363f79b8507585925757acc3e980a6c4 v24 850x600"></div>
                        <div class="interactionNotice">
                            <span class="icon"><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="hand-pointer" class="svg-inline--fa fa-hand-pointer fa-w-14" role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 617">
    <path fill="currentColor" d="M448,344.59v96a40.36,40.36,0,0,1-1.06,9.16l-32,136A40,40,0,0,1,376,616.59H168a40,40,0,0,1-32.35-16.47l-128-176a40,40,0,0,1,64.7-47.06L104,420.58v-276a40,40,0,0,1,80,0v200h8v-40a40,40,0,1,1,80,0v40h8v-24a40,40,0,1,1,80,0v24h8a40,40,0,1,1,80,0Zm-256,80h-8v96h8Zm88,0h-8v96h8Zm88,0h-8v96h8Z" transform="translate(0 -0.41)"></path>
    <path fill="currentColor" opacity="0.6" d="M239.76,234.78A27.5,27.5,0,0,1,217,192a87.76,87.76,0,1,0-145.9,0A27.5,27.5,0,1,1,25.37,222.6,142.17,142.17,0,0,1,1.24,143.17C1.24,64.45,65.28.41,144,.41s142.76,64,142.76,142.76a142.17,142.17,0,0,1-24.13,79.43A27.47,27.47,0,0,1,239.76,234.78Z" transform="translate(0 -0.41)"></path>
</svg></span>
                            <span class="label">Click to open interactive version</span>
                        </div>
                    </a>
                </figure>
</div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<h4 id="which-countries-have-eliminated-guinea-worm-disease">Which countries have eliminated guinea worm disease?<a class="deep-link" href="#which-countries-have-eliminated-guinea-worm-disease"></a></h4>
</div>



<div class="wp-block-column"></div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<p>In many countries, guinea worm disease has been completely eliminated.</p>



<p>Countries are certified as free of guinea worm disease if they have reported zero indigenous cases for at least three consecutive years while having active surveillance.<a id="ref-11" class="ref" href="#note-11"><sup>11</sup></a></p>



<p>On the map, you can see which countries are certified as being free of guinea worm disease. They are shown in blue. Using the timeline at the bottom of the chart you can see how each country’s status changed over time.</p>



<p>In 1996, 16 countries were known to be endemic for guinea worm disease. By 2021, only five countries remained endemic – Mali, Chad, South Sudan, Ethiopia, and Angola.</p>
</div>



<div class="wp-block-column">

                <figure data-grapher-src="https://ourworldindata.org/grapher/progress-towards-guinea-worm-disease-eradication" class="grapherPreview">
                    <a href="https://ourworldindata.org/grapher/progress-towards-guinea-worm-disease-eradication" target="_blank">
                        <div><img src="https://ourworldindata.org/exports/progress-towards-guinea-worm-disease-eradication_v11_850x600.svg" width="850" height="600" loading="lazy" data-no-lightbox="" alt="Progress towards guinea worm disease eradication v11 850x600"></div>
                        <div class="interactionNotice">
                            <span class="icon"><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="hand-pointer" class="svg-inline--fa fa-hand-pointer fa-w-14" role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 617">
    <path fill="currentColor" d="M448,344.59v96a40.36,40.36,0,0,1-1.06,9.16l-32,136A40,40,0,0,1,376,616.59H168a40,40,0,0,1-32.35-16.47l-128-176a40,40,0,0,1,64.7-47.06L104,420.58v-276a40,40,0,0,1,80,0v200h8v-40a40,40,0,1,1,80,0v40h8v-24a40,40,0,1,1,80,0v24h8a40,40,0,1,1,80,0Zm-256,80h-8v96h8Zm88,0h-8v96h8Zm88,0h-8v96h8Z" transform="translate(0 -0.41)"></path>
    <path fill="currentColor" opacity="0.6" d="M239.76,234.78A27.5,27.5,0,0,1,217,192a87.76,87.76,0,1,0-145.9,0A27.5,27.5,0,1,1,25.37,222.6,142.17,142.17,0,0,1,1.24,143.17C1.24,64.45,65.28.41,144,.41s142.76,64,142.76,142.76a142.17,142.17,0,0,1-24.13,79.43A27.47,27.47,0,0,1,239.76,234.78Z" transform="translate(0 -0.41)"></path>
</svg></span>
                            <span class="label">Click to open interactive version</span>
                        </div>
                    </a>
                </figure>
</div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column"></div>



<div class="wp-block-column">    <div class="block-wrapper"><div class="wp-block-owid-prominent-link with-image" data-no-lightbox="true" data-style="is-style-thin" data-title="When were countries certified free of guinea worm disease?"><a href="https://ourworldindata.org/grapher/year-country-was-certified-free-of-guinea-worm-disease" target="_blank"><figure><img src="https://ourworldindata.org/grapher/exports/year-country-was-certified-free-of-guinea-worm-disease.svg" alt="Year country was certified free of guinea worm disease" loading="lazy"></figure><div class="content-wrapper"><div class="title"><span>When were countries certified free of guinea worm disease?</span><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="arrow-right" class="svg-inline--fa fa-arrow-right " role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><path fill="currentColor" d="M438.6 278.6l-160 160C272.4 444.9 264.2 448 256 448s-16.38-3.125-22.62-9.375c-12.5-12.5-12.5-32.75 0-45.25L338.8 288H32C14.33 288 .0016 273.7 .0016 256S14.33 224 32 224h306.8l-105.4-105.4c-12.5-12.5-12.5-32.75 0-45.25s32.75-12.5 45.25 0l160 160C451.1 245.9 451.1 266.1 438.6 278.6z"></path></svg></div></div></a></div></div></div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<h4 id="we-are-close-to-eradicating-guinea-worm-disease-but-challenges-remain">We are close to eradicating guinea worm disease, but challenges remain<a class="deep-link" href="#we-are-close-to-eradicating-guinea-worm-disease-but-challenges-remain"></a></h4>
</div>



<div class="wp-block-column"></div>
</div><div class="wp-block-columns is-style-sticky-right">
<div class="wp-block-column">
<p>To eradicate guinea worm disease globally, there are several challenges we need to overcome.</p>



<p>We don’t know, for example, whether the Democratic Republic of Congo is free of guinea worm disease, because levels of monitoring have been insufficient to confirm it. This is shown in the map above.</p>



<p>A general challenge is that it takes around a year after infection for the worm to emerge from a person’s body. This is why countries need to monitor for new cases for several years after they have reported zero cases, in order to achieve certification.</p>



<p>Another problem is that a few countries, such as Chad and Ethiopia, have recently had outbreaks linked to dogs infected with the worms, which had not been seen before. That means extra efforts have been needed in recent years to prevent infections in dogs in those regions.<a id="ref-12" class="ref" href="#note-12"><sup>12</sup></a></p>



<p>Finally, it has been difficult to eliminate guinea worm disease in countries with violence and conflict, where healthcare workers are less able to treat and prevent infections.<a id="ref-13" class="ref" href="#note-13"><sup>13</sup></a></p>



<p>Despite these challenges, there has been a massive decline in guinea worm cases over time. Only 15 cases were reported globally in 2021. The world is so close to the goal and with dedicated effort, we may soon achieve it. After thousands of years, the entire world may soon be free of this debilitating disease.</p>
</div>



<div class="wp-block-column"></div>
</div><div class="wp-block-columns is-style-sticky-right"><div class="wp-block-column"><hr class="wp-block-separator"><p><em><strong>Keep reading on Our World in Data:</strong></em></p><div class="block-wrapper"><div class="wp-block-owid-prominent-link with-image" data-no-lightbox="true" data-style="is-style-thin" data-title="Clean Water"><a href="https://ourworldindata.org/water-access"><figure><img src="https://ourworldindata.org/uploads/2021/06/Clean-Water-thumbnail-150x79.png" data-high-res-src="https://ourworldindata.org/uploads/2021/06/Clean-Water-thumbnail.png" alt="Clean water thumbnail" loading="lazy"></figure><div class="content-wrapper"><div class="content">



</div><div class="title"><span>Clean Water</span><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="arrow-right" class="svg-inline--fa fa-arrow-right " role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><path fill="currentColor" d="M438.6 278.6l-160 160C272.4 444.9 264.2 448 256 448s-16.38-3.125-22.62-9.375c-12.5-12.5-12.5-32.75 0-45.25L338.8 288H32C14.33 288 .0016 273.7 .0016 256S14.33 224 32 224h306.8l-105.4-105.4c-12.5-12.5-12.5-32.75 0-45.25s32.75-12.5 45.25 0l160 160C451.1 245.9 451.1 266.1 438.6 278.6z"></path></svg></div></div></a></div></div><div class="block-wrapper"><div class="wp-block-owid-prominent-link with-image" data-no-lightbox="true" data-style="is-style-thin" data-title="Polio"><a href="https://ourworldindata.org/polio"><figure><img src="https://ourworldindata.org/uploads/2022/04/Polio-featured-image-150x59.png" data-high-res-src="https://ourworldindata.org/uploads/2022/04/Polio-featured-image.png" alt="Polio featured image" loading="lazy"></figure><div class="content-wrapper"><div class="content">



</div><div class="title"><span>Polio</span><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="arrow-right" class="svg-inline--fa fa-arrow-right " role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><path fill="currentColor" d="M438.6 278.6l-160 160C272.4 444.9 264.2 448 256 448s-16.38-3.125-22.62-9.375c-12.5-12.5-12.5-32.75 0-45.25L338.8 288H32C14.33 288 .0016 273.7 .0016 256S14.33 224 32 224h306.8l-105.4-105.4c-12.5-12.5-12.5-32.75 0-45.25s32.75-12.5 45.25 0l160 160C451.1 245.9 451.1 266.1 438.6 278.6z"></path></svg></div></div></a></div></div><p><strong>Acknowledgments:</strong> Hannah Ritchie and Max Roser provided very helpful guidance and comments that helped improve this post.</p></div><div class="wp-block-column"></div></div></section>
































































</div><footer class="article-footer"><div class="wp-block-columns"><div class="wp-block-column"><h3 id="endnotes">Endnotes</h3><ol class="endnotes"><li id="note-1"><p>Imtiaz, R., Hopkins, D. R., &amp; Ruiz-Tiben, E. (1990). Permanent disability from dracunculiasis. <em>The Lancet</em>, <em>336</em>(8715), 630. https://doi.org/10.1016/0140-6736(90)93427-Q</p></li><li id="note-2"><p>Biswas, G., Sankara, D. P., Agua-Agum, J., &amp; Maiga, A. (2013). Dracunculiasis (guinea worm disease): eradication without a drug or a vaccine. <em>Philosophical Transactions of the Royal Society B: Biological Sciences</em>, <em>368</em>(1623), 20120146. <a href="https://doi.org/10.1098/rstb.2012.0146">https://doi.org/10.1098/rstb.2012.0146</a>Sankara, D.P., Korkor, A.S., Agua-Agum, J., Biswas, G. (2016). Dracunculiasis (Guinea Worm Disease). In: Gyapong, J., Boatin, B. (eds) Neglected Tropical Diseases – Sub-Saharan Africa. Neglected Tropical Diseases. Springer, Cham. <a href="https://doi.org/10.1007/978-3-319-25471-5_3">https://doi.org/10.1007/978-3-319-25471-5_3</a> </p></li><li id="note-3"><p>Watts, S. (1998). An ancient scourge: the end of Dracunculiasis in Egypt. <em>Social Science &amp; Medicine</em>, <em>46</em>(7), 811–819. <a href="https://doi.org/10.1016/S0277-9536(97)00213-X">https://doi.org/10.1016/S0277-9536(97)00213-X</a> </p></li><li id="note-4"><p>Tayeh, A., Cairncross, S., &amp; Cox, F. E. (2017). Guinea worm: from Robert Leiper to eradication. <em>Parasitology</em>, <em>144</em>(12), 1643-1648.</p></li><li id="note-5"><p>Reddy, C. R. R. M., Narasaiah, I. L., &amp; Parvathi, G. (1969). Epidemiological studies on guinea-worm infection. Bulletin of the World Health Organization, 40(4), 521. <a href="https://www.ncbi.nlm.nih.gov/pmc/articles/PMC2556107/pdf/bullwho00225-0041.pdf">https://www.ncbi.nlm.nih.gov/pmc/articles/PMC2556107/pdf/bullwho00225-0041.pdf</a> </p></li><li id="note-6"><p>Molyneux, D., &amp; Sankara, D. P. (2017). Guinea worm eradication: Progress and challenges—should we beware of the dog?. <em>PLoS Neglected Tropical Diseases</em>, <em>11</em>(4), e0005495.</p></li><li id="note-7"><p>Hopkins, D. R., &amp; Ruiz-Tiben, E. (2011). Dracunculiasis (guinea worm disease): case study of the effort to eradicate guinea worm. <a href="https://www.cartercenter.org/resources/pdfs/news/health_publications/selendy-waterandsanitationrelateddiseases-chapt10.pdf">https://www.cartercenter.org/resources/pdfs/news/health_publications/selendy-waterandsanitationrelateddiseases-chapt10.pdf</a><br>Cleveland, C. A., Garrett, K. B., Box, E. K., Eure, Z., Majewska, A. A., Wilson, J. A., &amp; Yabsley, M. J. (2020). Cooking copepods: The survival of cyclopoid copepods (Crustacea: Copepoda) in simulated provisioned water containers and implications for the Guinea Worm Eradication Program in Chad, Africa. <em>International Journal of Infectious Diseases</em>, <em>95</em>, 216-220.</p></li><li id="note-8"><p>In dry climates, the disease is more common in rainy seasons when water accumulates in ponds and wells. In wet climates, the disease is more common in dry seasons when water is drying up and becoming stagnant.<br>Muller, R. (1979). Guinea worm disease: epidemiology, control, and treatment. <em>Bulletin of the World Health Organization</em>, <em>57</em>(5), 683.</p></li><li id="note-9"><p>Hopkins, D. R., Ruiz-Tiben, E., Eberhard, M. L., Weiss, A., Withers, P. C., Roy, S. L., &amp; Sienko, D. G. (2018). Dracunculiasis Eradication: Are We There Yet?. <em>The American journal of tropical medicine and hygiene</em>, <em>99</em>(2), 388–395. <a href="https://doi.org/10.4269/ajtmh.18-0204">https://doi.org/10.4269/ajtmh.18-0204</a> </p></li><li id="note-10"><p>Hopkins, D. R., &amp; Ruiz-Tiben, E. (2011). Dracunculiasis (guinea worm disease): case study of the effort to eradicate guinea worm. https://www.cartercenter.org/resources/pdfs/news/health_publications/selendy-waterandsanitationrelateddiseases-chapt10.pdf </p></li><li id="note-11"><p>They are certified by the International Commission for the Certification of Dracunculiasis Eradication (ICCDE), which was set up in 1995.<br><em>The International Commission for the Certification of Dracunculiasis Eradication – About us.</em> (n.d.). World Health Organization. Retrieved June 3, 2022, from https://www.who.int/groups/international-commission-for-the-certification-of-dracunculiasis-eradication/about</p></li><li id="note-12"><p>Molyneux, D., &amp; Sankara, D. P. (2017). Guinea worm eradication: Progress and challenges—should we beware of the dog?. <em>PLoS Neglected Tropical Diseases</em>, <em>11</em>(4), e0005495.<br>Hopkins, D. R., Ruiz-Tiben, E., Eberhard, M. L., Weiss, A., Withers, P. C., Roy, S. L., &amp; Sienko, D. G. (2018). Dracunculiasis Eradication: Are We There Yet? <em>The American Journal of Tropical Medicine and Hygiene</em>, <em>99</em>(2), 388–395. <a href="https://doi.org/10.4269/ajtmh.18-0204">https://doi.org/10.4269/ajtmh.18-0204</a> </p></li><li id="note-13"><p>Kelly-Hope, L. A., &amp; Molyneux, D. H. (2021). Quantifying conflict zones as a challenge to certification of Guinea worm eradication in Africa: a new analytical approach. <em>BMJ open</em>, <em>11</em>(8), e049732.<br>In some cases, the eradication effort has worked around conflicts or addressed them. For example, in 1995, former US president Jimmy Carter was involved in negotiating a ceasefire during the Second Sudanese Civil War, to allow healthcare workers to begin efforts to eradicate guinea worm disease in the region.<br>Hopkins, D. R., &amp; Ruiz-Tiben, E. (2011). Dracunculiasis (guinea worm disease): case study of the effort to eradicate guinea worm. <a href="https://www.cartercenter.org/resources/pdfs/news/health_publications/selendy-waterandsanitationrelateddiseases-chapt10.pdf">https://www.cartercenter.org/resources/pdfs/news/health_publications/selendy-waterandsanitationrelateddiseases-chapt10.pdf</a> </p></li></ol><h3 id="licence">Reuse our work freely</h3><p>All visualizations, data, and code produced by Our World in Data are completely open access under the <a href="https://creativecommons.org/licenses/by/4.0/" target="_blank" rel="noopener noreferrer">Creative Commons BY license</a>. You have the permission to use, distribute, and reproduce these in any medium, provided the source and authors are credited.</p><p>The data produced by third parties and made available by Our World in Data is subject to the license terms from the original third-party authors. We will always indicate the original source of the data in our documentation, so you should always check the license of any such third-party data before use and redistribution.</p><p>All of <a href="/how-to-use-our-world-in-data#how-to-embed-interactive-charts-in-your-article">our charts can be embedded</a> in any site.</p></div><div class="wp-block-column"></div></div></footer></div></div></div></article></main><div id="wpadminbar" style="display:none"><div class="quicklinks" id="wp-toolbar" role="navigation" aria-label="Toolbar"><ul id="wp-admin-bar-root-default" class="ab-top-menu"><li id="wp-admin-bar-site-name" class="menupop"><a class="ab-item" aria-haspopup="true" href="https://owid.cloud/wp/wp-admin">Wordpress</a></li> <li id="wp-admin-bar-edit"><a class="ab-item" href="https://owid.cloud/wp/wp-admin/post.php?post=26401&amp;action=edit">Edit Page</a></li></ul></div></div><section class="donate-footer"><div class="wrapper"><div class="owid-row flex-align-center"><div class="owid-col owid-col--lg-3 owid-padding-bottom--sm-3"><p>Our World in Data is free and accessible for everyone.</p><p>Help us do this work by making a donation.</p></div><div class="owid-col owid-col--lg-1"><a href="/donate" class="owid-button donate-button" data-track-note="donate-footer"><span class="label">Donate now</span><span class="icon"><svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="angle-right" class="svg-inline--fa fa-angle-right " role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 512"><path fill="currentColor" d="M64 448c-8.188 0-16.38-3.125-22.62-9.375c-12.5-12.5-12.5-32.75 0-45.25L178.8 256L41.38 118.6c-12.5-12.5-12.5-32.75 0-45.25s32.75-12.5 45.25 0l160 160c12.5 12.5 12.5 32.75 0 45.25l-160 160C80.38 444.9 72.19 448 64 448z"></path></svg></span></a></div></div></div></section><footer class="site-footer"><div class="wrapper"><div class="owid-row"><div class="owid-col owid-col--lg-1"><ul><li><a href="/about" data-track-note="footer-navigation">About</a></li><li><a href="/about#contact" data-track-note="footer-navigation">Contact</a></li><li><a href="/feedback" data-track-note="footer-navigation">Feedback</a></li><li><a href="/jobs" data-track-note="footer-navigation">Jobs</a></li><li><a href="/funding" data-track-note="footer-navigation">Funding</a></li><li><a href="/about/how-to-use-our-world-in-data" data-track-note="footer-navigation">How to use</a></li><li><a href="/donate" data-track-note="footer-navigation">Donate</a></li><li><a href="/privacy-policy" data-track-note="footer-navigation">Privacy policy</a></li></ul></div><div class="owid-col owid-col--lg-1"><ul><li><a href="/blog" data-track-note="footer-navigation">Latest work</a></li><li><a href="/charts" data-track-note="footer-navigation">All charts</a></li></ul><ul><li><a href="https://twitter.com/OurWorldInData" data-track-note="footer-navigation">Twitter</a></li><li><a href="https://www.facebook.com/OurWorldinData" data-track-note="footer-navigation">Facebook</a></li><li><a href="https://instagram.com/ourworldindata_official" data-track-note="footer-navigation">Instagram</a></li><li><a href="https://github.com/owid" data-track-note="footer-navigation">GitHub</a></li><li><a href="/feed" data-track-note="footer-navigation">RSS Feed</a></li></ul></div><div class="owid-col owid-col--lg-1"><div class="logos"><a href="https://www.oxfordmartin.ox.ac.uk/global-development" class="partner-logo" data-track-note="footer-navigation"><img src="https://ourworldindata.org/oms-logo.svg" alt="Oxford Martin School logo" loading="lazy"/></a><a href="/owid-at-ycombinator" class="partner-logo" data-track-note="footer-navigation"><img src="https://ourworldindata.org/yc-logo.png" alt="Y Combinator logo" loading="lazy"/></a></div></div><div class="owid-col flex-2"><div class="legal"><p>Licenses: All visualizations, data, and articles produced by Our World in Data are open access under the <a href="https://creativecommons.org/licenses/by/4.0/" target="_blank" rel="noopener noreferrer">Creative Commons BY license</a>. You have permission to use, distribute, and reproduce these in any medium, provided the source and authors are credited. All the software and code that we write is open source and made available via GitHub under the permissive <a href="https://github.com/owid/owid-grapher/blob/master/LICENSE.md " target="_blank" rel="noopener noreferrer">MIT license</a>. All other material, including data produced by third parties and made available by Our World in Data, is subject to the license terms from the original third-party authors.</p><p>Please consult our full <a href="/about#legal">legal disclaimer</a>.</p><p><a href="https://global-change-data-lab.org/" class="partner-logo gcdl-logo" data-track-note="footer-navigation"><img src="https://ourworldindata.org/gcdl-logo.svg" alt="Global Change Data Lab logo" loading="lazy"/></a>Our World In Data is a project of the <a href="https://global-change-data-lab.org/">Global Change Data Lab</a>, a registered charity in England and Wales (Charity Number 1186433).</p></div></div></div></div><div class="site-tools"></div><script src="https://polyfill.io/v3/polyfill.min.js?features=es6,fetch,URL,IntersectionObserver,IntersectionObserverEntry"></script><script src="https://ourworldindata.org/assets/commons.js"></script><script src="https://ourworldindata.org/assets/vendors.js"></script><script src="https://ourworldindata.org/assets/owid.js"></script><script>window.runSiteFooterScripts()</script></footer><script>
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   runTableOfContents({"headings":[],"pageTitle":"Guinea worm disease is close to being eradicated – how was this progress achieved?"})
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   runRelatedCharts(undefined)
</script><!-- Google Tag Manager (noscript) -->
<noscript><iframe src="https://www.googletagmanager.com/ns.html?id=GTM-N2D4V8S"
            height="0" width="0" style="display:none;visibility:hidden"></iframe></noscript>
<!-- End Google Tag Manager (noscript) --></body></html>

]]

ExampleContent.BASE_64_IMAGE_SRC = "data:image/jpeg;base64,iVBORw0KGgoAAAANSUhEUgAAB9AAAAXICAMAAADV/KWUAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAVZQTFRF3+br6l0l/f3+5uvv9vj6+"

return ExampleContent
