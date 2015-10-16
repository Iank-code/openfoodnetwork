require 'open_food_network/spree_api_key_loader'

Spree::Admin::OrdersController.class_eval do
  include OpenFoodNetwork::SpreeApiKeyLoader
  before_filter :load_spree_api_key, :only => :bulk_management

  # We need to add expections for collection actions other than :index here
  # because spree_auth_devise causes load_order to be called, which results
  # in an auth failure as the @order object is nil for collection actions
  before_filter :check_authorization, except: [:bulk_management, :managed]

  # After updating an order, the fees should be updated as well
  # Currently, adding or deleting line items does not trigger updating the
  # fees! This is a quick fix for that.
  # TODO: update fees when adding/removing line items
  # instead of the update_distribution_charge method.
  after_filter :update_distribution_charge, :only => :update

  respond_override :index => { :html =>
    { :success => lambda {
      # Filter orders to only show those distributed by current user (or all for admin user)
      @orders = @search.result.includes([:user, :shipments, :payments]).
        distributed_by_user(spree_current_user).
        page(params[:page]).
        per(params[:per_page] || Spree::Config[:orders_per_page])
      # Filter orders by distributor
      if params[:distributor_ids]
        @orders = @orders.where(distributor_id: params[:distributor_ids])
      end
      if params[:order_cycle_ids]
        @orders = @orders.where(order_cycle_id: params[:order_cycle_ids])
      end
    } } }

  # Overwrite to use confirm_email_for_customer instead of confirm_email.
  # This uses a new template. See mailers/spree/order_mailer_decorator.rb.
  def resend
    Spree::OrderMailer.confirm_email_for_customer(@order.id, true).deliver
    flash[:success] = t(:order_email_resent)

    respond_with(@order) { |format| format.html { redirect_to :back } }
  end

  def invoice
    pdf = render_to_string pdf: "invoice-#{@order.number}.pdf", template: "spree/admin/orders/invoice", formats: [:html], encoding: "UTF-8"
    Spree::OrderMailer.invoice_email(@order.id, pdf).deliver
    flash[:success] = t(:invoice_email_sent)

    respond_with(@order) { |format| format.html { redirect_to edit_admin_order_path(@order) } }
  end

  def update_distribution_charge
    @order.update_distribution_charge!
  end

  def managed
    permissions = OpenFoodNetwork::Permissions.new(spree_current_user)
    @orders = permissions.editable_orders.order(:id).ransack(params[:q]).result.page(params[:page]).per(params[:per_page])
    render json: @orders, each_serializer: Api::Admin::OrderSerializer
  end
end
