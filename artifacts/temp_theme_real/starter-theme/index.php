<?php
/**
 * The main template file.
 *
 * @package Starter_Theme
 * @since   1.0.0
 */

defined( 'ABSPATH' ) || exit;

get_header();
?>

<main class="site-content" role="main">
	<?php
	if ( have_posts() ) :
		while ( have_posts() ) :
			the_post();
			?>
			<article id="post-<?php the_ID(); ?>" <?php post_class(); ?>>
				<header class="entry-header">
					<h2 class="entry-title">
						<a href="<?php the_permalink(); ?>">
							<?php the_title(); ?>
						</a>
					</h2>
				</header>

				<div class="entry-content">
					<?php the_excerpt(); ?>
				</div>
			</article>
			<?php
		endwhile;

		the_posts_navigation();

	else :
		?>
		<p><?php esc_html_e( 'No posts found.', 'starter-theme' ); ?></p>
		<?php
	endif;
	?>
</main>

<?php
get_footer();
