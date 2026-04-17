<?php
/**
 * Starter Theme functions and definitions.
 *
 * @package Starter_Theme
 * @since   1.0.0
 */

defined( 'ABSPATH' ) || exit;

/**
 * Set up theme defaults and register support for various WordPress features.
 *
 * @since 1.0.0
 * @return void
 */
function starter_theme_setup() {
	// Add default posts and comments RSS feed links to head.
	add_theme_support( 'automatic-feed-links' );

	// Let WordPress manage the document title.
	add_theme_support( 'title-tag' );

	// Enable support for Post Thumbnails on posts and pages.
	add_theme_support( 'post-thumbnails' );

	// Switch default core markup for search form, comment form, and comments
	// to output valid HTML5.
	add_theme_support(
		'html5',
		array(
			'search-form',
			'comment-form',
			'comment-list',
			'gallery',
			'caption',
			'style',
			'script',
		)
	);

	// Register navigation menu.
	register_nav_menus(
		array(
			'primary' => esc_html__( 'Primary Menu', 'starter-theme' ),
		)
	);
}
add_action( 'after_setup_theme', 'starter_theme_setup' );

/**
 * Enqueue scripts and styles.
 *
 * @since 1.0.0
 * @return void
 */
function starter_theme_scripts() {
	wp_enqueue_style(
		'starter-theme-style',
		get_stylesheet_uri(),
		array(),
		wp_get_theme()->get( 'Version' )
	);
}
add_action( 'wp_enqueue_scripts', 'starter_theme_scripts' );

/**
 * Security: Remove WordPress version from head.
 *
 * @since 1.0.0
 * @return string
 */
function starter_theme_remove_version() {
	return '';
}
add_filter( 'the_generator', 'starter_theme_remove_version' );
