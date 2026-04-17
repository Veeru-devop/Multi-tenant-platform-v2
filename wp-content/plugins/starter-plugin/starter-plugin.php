<?php
/**
 * Starter Plugin
 *
 * @package           Starter_Plugin
 * @author            DevOps Team
 * @license           GPL-2.0-or-later
 *
 * @wordpress-plugin
 * Plugin Name:       Starter Plugin
 * Plugin URI:        https://github.com/example/wp-multitenant-platform
 * Description:       A minimal starter plugin for the WordPress Multitenancy Platform. Adds tenant info to the admin dashboard.
 * Version:           1.0.0
 * Requires at least: 6.0
 * Requires PHP:      8.0
 * Author:            DevOps Team
 * Author URI:        https://github.com/example
 * License:           GPL v2 or later
 * License URI:       https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain:       starter-plugin
 */

defined( 'ABSPATH' ) || exit;

define( 'STARTER_PLUGIN_VERSION', '1.0.0' );
define( 'STARTER_PLUGIN_FILE', __FILE__ );

/**
 * Add a dashboard widget showing tenant environment info.
 *
 * @since 1.0.0
 * @return void
 */
function starter_plugin_add_dashboard_widget() {
	wp_add_dashboard_widget(
		'starter_plugin_tenant_info',
		esc_html__( 'Tenant Information', 'starter-plugin' ),
		'starter_plugin_dashboard_widget_render'
	);
}
add_action( 'wp_dashboard_setup', 'starter_plugin_add_dashboard_widget' );

/**
 * Render the dashboard widget content.
 *
 * @since 1.0.0
 * @return void
 */
function starter_plugin_dashboard_widget_render() {
	$db_host = defined( 'DB_HOST' ) ? DB_HOST : 'unknown';
	$db_name = defined( 'DB_NAME' ) ? DB_NAME : 'unknown';

	printf(
		'<table class="widefat striped">
			<tbody>
				<tr><th>%s</th><td>%s</td></tr>
				<tr><th>%s</th><td>%s</td></tr>
				<tr><th>%s</th><td>%s</td></tr>
				<tr><th>%s</th><td>%s</td></tr>
				<tr><th>%s</th><td>%s</td></tr>
			</tbody>
		</table>',
		esc_html__( 'Hostname', 'starter-plugin' ),
		esc_html( gethostname() ),
		esc_html__( 'DB Host', 'starter-plugin' ),
		esc_html( $db_host ),
		esc_html__( 'DB Name', 'starter-plugin' ),
		esc_html( $db_name ),
		esc_html__( 'PHP Version', 'starter-plugin' ),
		esc_html( phpversion() ),
		esc_html__( 'Plugin Version', 'starter-plugin' ),
		esc_html( STARTER_PLUGIN_VERSION )
	);
}

/**
 * Add a custom REST API endpoint for health checks.
 *
 * @since 1.0.0
 * @return void
 */
function starter_plugin_register_routes() {
	register_rest_route(
		'starter/v1',
		'/health',
		array(
			'methods'             => 'GET',
			'callback'            => 'starter_plugin_health_check',
			'permission_callback' => '__return_true',
		)
	);
}
add_action( 'rest_api_init', 'starter_plugin_register_routes' );

/**
 * Health check endpoint callback.
 *
 * @since 1.0.0
 * @return WP_REST_Response
 */
function starter_plugin_health_check() {
	global $wpdb;

	$db_ok = false;
	// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery,WordPress.DB.DirectDatabaseQuery.NoCaching
	$result = $wpdb->get_var( 'SELECT 1' );
	if ( '1' === $result ) {
		$db_ok = true;
	}

	$data = array(
		'status'   => $db_ok ? 'healthy' : 'degraded',
		'hostname' => gethostname(),
		'db_ok'    => $db_ok,
		'version'  => STARTER_PLUGIN_VERSION,
		'wp'       => get_bloginfo( 'version' ),
		'php'      => phpversion(),
	);

	$status_code = $db_ok ? 200 : 503;

	return new WP_REST_Response( $data, $status_code );
}
